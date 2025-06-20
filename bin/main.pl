#!/usr/bin/perl
use strict;
use warnings;
use DBI;
use Term::ProgressBar;
use List::MoreUtils qw(uniq);
use Data::Dumper;

# CONFIGURATION
my $database = 'SET_YOUR_TAXOBASE_DB';
my $dsn = "DBI:SQLite:dbname=$database";

# DB Connection
my $dbh = DBI->connect($dsn, "", "", { RaiseError => 1 }) or die $DBI::errstr;

# Read Input
my $input_file = shift or die "Usage: $0 input.tsv\n";
open my $fh, "<", $input_file or die $!;
my @lines = <$fh>;
close $fh;

# Define a mismatch log file
my $mismatch_log = "logs/mismatch_taxa.tsv";

# Utils
sub clean_taxon {
    my $t = shift;
    $t =~ s/[()\[\]']+//g;
    $t =~ s/;__+/;/g;
    return $t;
}

sub normalize_db_field {
    my ($val) = @_;
    return '_' unless defined $val;
    $val = lc($val);
    $val =~ s/[^a-z0-9]+/_/g;      # Replace non-alphanumeric with _
    $val =~ s/_+/_/g;              # Collapse multiple underscores
    $val =~ s/^_//;                # Trim leading _
    $val =~ s/_$//;                # Trim trailing _
    return ($val eq '') ? '_' : $val;
}

sub parse_taxonomy {
    my $tax = shift;
    my @ranks = split /;/, $tax;
    my @levels = qw(KINGDOM PHYLUM CLASS ORDER_TAX FAMILY GENUS SPECIES);
    my @clean;

    for my $i (0..6) {
        my $val = $ranks[$i] // "_";
        $val =~ s/^[kpcfogs]_+//;  # strip prefixes like k__, p__, etc.
        push @clean, ($val eq '') ? "_" : $val;
    }
    return @clean;
}

sub smart_species_format {
    my ($genus, $species) = @_;
    return $species unless defined $genus && defined $species;

    # Normalize (just in case)
    $genus = normalize_db_field($genus);
    $species = normalize_db_field($species);

    # Check if species starts with genus and has more characters
    if ($species ne $genus && $species =~ /^$genus\_+/) {
        my $rest = $species;
        $rest =~ s/^$genus\_+//;
        return "$genus=$rest";
    }

    return $species;
}

sub get_tax_id {
    my ($kingdom, $phylum, $class, $order, $family, $genus, $species, $full_id) = @_;
    my $sql = "SELECT * FROM TAXONOMY WHERE KINGDOM=? AND PHYLUM=? AND CLASS=? AND ORDER_TAX=? AND FAMILY=? AND GENUS=? AND SPECIES=?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($kingdom, $phylum, $class, $order, $family, $genus, $species);
    my @row = $sth->fetchrow_array;
    return $row[0] if @row;

    my $norm_no_rank = normalize_db_field($full_id);

    # Try NO_RANK using normalized form
    $sql = "SELECT * FROM TAXONOMY WHERE NO_RANK=?";
    $sth = $dbh->prepare($sql);
    $sth->execute($norm_no_rank);
    @row = $sth->fetchrow_array;
    return $row[0] if @row;

    # No match found — call ncbi_agent.pl
    my $safe_query = $full_id;
    $safe_query =~ s/'//g;  # Remove any quotes

    print "🕒 Fetching from NCBI: $safe_query\n";

    # Delay to respect NCBI's API rate limits
    select(undef, undef, undef, 1.0);  # sleep ~340 milliseconds


    unlink "taxonomy_output.txt" if -e "taxonomy_output.txt";
    my $system_cmd = "perl bin/ncbi_agent.pl \"$safe_query\"";
    system($system_cmd) == 0 or die "Failed to run ncbi_agent.pl on $safe_query\n";

    my $status = system($system_cmd);
    if ($status != 0 || ! -e "taxonomy_output.txt") {
        warn "❌ Skipping $safe_query — ncbi_agent.pl failed or output file missing.\n";
        return "NO_TAX_ID";
    }

    # Parse taxonomy_output.txt
    open my $in, "<", "taxonomy_output.txt" or do {
        warn "❌ Cannot read taxonomy_output.txt after $safe_query\n";
        return "NO_TAX_ID";
    };

    <$in>;  # skip header
    my $line = <$in>;
    close $in;

    unless (defined $line && $line =~ /\S/) {
        warn "❌ taxonomy_output.txt is empty after $safe_query\n";
        return "NO_TAX_ID";
    }

    chomp $line;
    my @fields = split /\t/, $line;

    # Validate that the NO_RANK field matches the full query
    my $reported_query = $fields[-1];

    my $norm_expected = normalize_db_field($full_id);
    my $norm_actual   = normalize_db_field($reported_query);

    if ($norm_expected ne $norm_actual) {
        # Accept if the match is a prefix (likely a strain was trimmed)
        if (index($norm_expected, $norm_actual) == 0) {
            warn "⚠ Strain-level detail dropped: accepted $norm_actual as a match for $norm_expected\n";
        } else {
            warn "❌ taxonomy_output.txt mismatch: expected $norm_expected but got $norm_actual\n";

            # Log mismatch lineage to logs/mismatch_taxa.tsv
            open my $logfh, ">>", $mismatch_log or die "Cannot open $mismatch_log: $!\n";

            # Write header if file is new
            if (-z $mismatch_log) {
                print $logfh join("\t", "ORIGINAL_QUERY", "REPORTED_QUERY", qw(TAX_ID SUPERKINGDOM KINGDOM PHYLUM CLASS ORDER FAMILY GENUS SPECIES NO_RANK)), "\n";
            }

            my @fields_to_log = (
                $full_id,            # ORIGINAL_QUERY (raw input)
                $reported_query,     # REPORTED_QUERY (returned by NCBI)
                @fields[1..10]       # Tax ID + full lineage
            );

            print $logfh join("\t", map { normalize_db_field($_) } @fields_to_log), "\n";
            close $logfh;
        
            return "NO_TAX_ID";
        }
    }


    # Check if taxonomy_output.txt is empty or invalid
    open $in, "<", "taxonomy_output.txt" or die "taxonomy_output.txt not found\n";
    <$in>;  # skip header
    $line = <$in>;
    close $in;

    unless (defined $line && $line =~ /\S/) {
        warn "❌ Skipping $safe_query — taxonomy_output.txt was empty.\n";
        return "NO_TAX_ID";
    }

    chomp $line;
    @fields = split /\t/, $line;

    # Verify expected number of fields
    unless (@fields >= 10) {
        warn "❌ Skipping $safe_query — taxonomy_output.txt had incomplete data.\n";
        return "NO_TAX_ID";
    }


    # Read taxonomy_output.txt
    open $in, "<", "taxonomy_output.txt" or die "taxonomy_output.txt not found\n";
    my $header = <$in>;
    $line = <$in>;
    close $in;

    chomp $line;
    @fields = split /\t/, $line;

    my ($query_id, $taxid, $superkingdom_api, $kingdom_api, $phylum_api, $class_api, $order_api, $family_api, $genus_api, $species_api) = @fields;

    # Check if NO_RANK already exists (case-insensitive)
    my $check_sth = $dbh->prepare("SELECT TAX_ID FROM TAXONOMY WHERE LOWER(NO_RANK) = LOWER(?)");
    
    $check_sth->execute($norm_no_rank);

    my ($existing_taxid) = $check_sth->fetchrow_array;

    if ($existing_taxid) {
        warn "⚠ Duplicate NO_RANK detected: $full_id already exists (TAX_ID=$existing_taxid), skipping insert\n";
        return $existing_taxid;
    }

    # Insert using updated fields
    my $stmt = $dbh->prepare("INSERT INTO TAXONOMY VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute(
        "ncbi_api",
        normalize_db_field($taxid),
        normalize_db_field($superkingdom_api),
        normalize_db_field($kingdom_api),
        normalize_db_field($phylum_api),
        normalize_db_field($class_api),
        normalize_db_field($order_api),
        normalize_db_field($family_api),
        normalize_db_field($genus_api),
        smart_species_format($genus_api, $species_api),
        $norm_no_rank
    );

    return $dbh->last_insert_id(undef, undef, "TAXONOMY", undef);
}


# Unique Queries
print "Extracting unique taxonomy terms...\n";
my %unique;
foreach (@lines) {
    my ($query) = split /\t/;
    $query = clean_taxon($query);
    $unique{$query} = 1;
}

# TaxID Mapping
print "Mapping tax_ids...\n";
my %taxid_of;
my $pb = Term::ProgressBar->new(scalar keys %unique);
my $count = 0;

foreach my $query (keys %unique) {
    my @fields = parse_taxonomy($query);
    my $tax_id = get_tax_id(@fields, $query);
    $taxid_of{$query} = $tax_id;
    $pb->update(++$count);
}

# Output Table
print "Generating output file...\n";
(my $outfile = $input_file) =~ s/\.[^.]+$//;  # Remove extension (e.g., .txt, .tsv)
$outfile .= "_taxonomyXcounts.txt";
open my $out, ">", $outfile or die "Cannot open $outfile: $!\n";
print $out join("\t", qw(TAX_ID SAMPLE_ID READ_COUNTS SOURCE ITIS_NUMBER SUPERKINGDOM KINGDOM PHYLUM CLASS ORDER_TAX FAMILY GENUS SPECIES)), "\n";

$pb = Term::ProgressBar->new(scalar @lines);
$count = 0;

foreach (@lines) {
    chomp;
    my ($query, $assembly_id, $count) = split /\t/;
    $query = clean_taxon($query);

    my @row = ("NO_TAX_ID") x 13;
    my $tax_id = $taxid_of{$query} // "NO_TAX_ID";

    if ($tax_id ne "NO_TAX_ID") {
        my $sth = $dbh->prepare("SELECT * FROM TAXONOMY WHERE TAX_ID = ?");
        $sth->execute($tax_id);
        @row = $sth->fetchrow_array;
        @row = map { $_ // "" } @row;
    }

    my @output_fields = (
        normalize_db_field($tax_id),
        normalize_db_field($assembly_id),
        normalize_db_field($count),
        map { normalize_db_field($_) } @row[1..10],
    );
    print $out join("\t", @output_fields), "\n";

    $pb->update(++$count);
}

close $out;
print "Done.\n";
