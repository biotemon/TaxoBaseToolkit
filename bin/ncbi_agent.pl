#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON qw(decode_json);
use XML::Simple;
use URI::Escape;
use List::MoreUtils qw(uniq);

# IDENTIFY TO NCBI
my $email = 'SET_YOUR_EMAIL';
my $api_key = 'SET_YOUR_APIKEY';

# Initialize HTTP agent globally
my $ua = LWP::UserAgent->new;
$ua->agent("LagunaVerdeBot/1.0 ($email)");

#Initialize log file
my $not_found_log = "logs/not_found_taxa.log";

# Load PHYLUM → KINGDOM/SUPERKINGDOM dictionary
my %phylum_dict;
open my $dict, "<", "data/phylum_dictionary.txt" or die "Cannot open phylum_dictionary.txt\n";
while (<$dict>) {
    next if $. == 1 || /^\s*$/;  # skip header or blank lines
    chomp;
    my ($phylum, $kingdom, $superkingdom) = split /\t+/;
    $phylum = defined($phylum) ? lc($phylum =~ s/\s+/_/gr) : '_';
    $kingdom = defined($kingdom) ? lc($kingdom =~ s/\s+/_/gr) : '_';
    $superkingdom = defined($superkingdom) ? lc($superkingdom =~ s/\s+/_/gr) : '_';
    $phylum_dict{$phylum} = [$kingdom || '_', $superkingdom || '_'];
}
close $dict;

# Retry wrapper for NCBI GET requests
sub safe_get {
    my ($url, $retries) = @_;
    $retries ||= 5;

    for my $attempt (1 .. $retries) {
        my $res = eval { $ua->get($url) };

        if ($res && $res->is_success) {
            return $res;
        }

        if ($@ || !$res) {
            warn "⏳ Connection error or timeout on attempt $attempt. Retrying...\n";
        } elsif ($res->code == 429) {
            warn "⏳ Rate limited (429) on attempt $attempt. Retrying...\n";
        } elsif ($res->code == 500) {
            warn "⏳ Server error (500) on attempt $attempt. Retrying...\n";
        } else {
            warn "⏳ Unexpected HTTP error (".$res->code.") on attempt $attempt. Retrying...\n";
        }

        # Wait exponentially longer each time
        sleep(2 ** $attempt);
    }

    die "❌ Failed after $retries attempts to fetch: $url\n";
}


# Generate fallback versions of the query
sub generate_query_candidates {
    my ($q) = @_;
    my @variants;
    $q =~ s/_/ /g;
    push @variants, $q;

    # Remove common noise words
    my $simplified = $q;
    $simplified =~ s/\b(str|strain|isolate|clone|subsp|subspecies|var|variant|group|complex|pathovar)\b\s*//gi;
    push @variants, $simplified if $simplified ne $q;

    # Try truncating after first two words
    if ($simplified =~ /^(\S+\s+\S+)/) {
        push @variants, $1;
    }

    return uniq @variants;
}

# Try to fetch TaxID smartly
sub get_taxid_from_ncbi {
    my ($original_query) = @_;
    my @candidates = generate_query_candidates($original_query);

    foreach my $candidate (@candidates) {
        my $escaped_query = uri_escape($candidate);
        my $search_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=taxonomy&term=$escaped_query&retmode=json&email=$email";
        $search_url .= "&api_key=$api_key" if $api_key;

        my $search_response = safe_get($search_url);
        my $search_data = eval { decode_json($search_response->decoded_content) };
        next unless $search_data && $search_data->{esearchresult}{idlist};

        my $taxid = $search_data->{esearchresult}{idlist}[0];
        if ($taxid) {
            print "✅ Found TaxID $taxid for cleaned query: $candidate\n";
            return ($taxid, $candidate);
        }
    }

    # No success
    return (undef, undef);
}

# MAIN PROGRAM
my $query_raw = shift @ARGV or die "Usage: $0 'organism name'\n";
(my $query = $query_raw) =~ s/_/ /g;

# Step 1: Fetch TaxID using smart fallback
my ($taxid, $used_query) = get_taxid_from_ncbi($query);

unless ($taxid) {
    warn "❌ No TaxID found for: $query (after fallback attempts)\n";

    # Log into not_found_taxa.log
    open my $logfh, ">>", $not_found_log or die "Cannot open $not_found_log for writing: $!\n";
    print $logfh "$query_raw\n";   # Log the original query form
    close $logfh;

    exit(0);   # Exit gracefully with non-zero exit code
}


# Use the cleaned-up query for downstream
$query = $used_query;

# Step 2: Fetch taxonomy lineage
my $fetch_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi";
$fetch_url .= "?db=taxonomy&id=" . uri_escape($taxid) . "&retmode=xml&email=$email";
$fetch_url .= "&api_key=$api_key" if $api_key;
my $fetch_response = safe_get($fetch_url);

my $xml = eval {
    XMLin(
        $fetch_response->decoded_content,
        ForceArray => ['Taxon'],
        KeyAttr    => []
    )
};
die "Failed to parse XML\n" unless $xml;

# Parse taxonomy
my $main_taxon = (ref $xml->{Taxon} eq 'ARRAY') ? $xml->{Taxon}[0] : $xml->{Taxon};

my %taxonomy;
if (ref $main_taxon->{LineageEx}{Taxon} eq 'ARRAY') {
    foreach my $tax (@{ $main_taxon->{LineageEx}{Taxon} }) {
        my $rank = $tax->{Rank} // next;
        my $name = $tax->{ScientificName} // next;
        $taxonomy{$rank} = $name;
    }
}
$taxonomy{species} = $main_taxon->{ScientificName} if $main_taxon->{Rank} eq 'species';

# Normalize and apply dictionary logic
my @ranks = qw(superkingdom kingdom phylum class order family genus species);
my %normalized;
foreach my $rank (@ranks) {
    my $val = $taxonomy{$rank} // '_';
    $val = lc($val);
    $val =~ s/\s+/_/g;
    $normalized{$rank} = $val;
}

# Override with dictionary if available
my $phylum = $normalized{phylum};
if (exists $phylum_dict{$phylum}) {
    ($normalized{kingdom}, $normalized{superkingdom}) = @{ $phylum_dict{$phylum} };
}

# Output to file
open my $out, ">", "taxonomy_output.txt" or die $!;
print $out join("\t", "query", "taxid", @ranks), "\n";
print $out join("\t",
    lc($query_raw) =~ s/\s+/_/gr,
    $taxid,
    @normalized{@ranks}
), "\n";
close $out;

print "✅ Final taxonomy written to taxonomy_output.txt\n";
