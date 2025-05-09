# TaxoBase Toolkit

This toolkit provides a portable pipeline to normalize and annotate microbial and viral taxonomies using a local SQLite database and the NCBI taxonomy API.

## Components

- `main.pl` — main pipeline script
- `ncbi_agent.pl` — supplemental taxonomy fetcher
- `phylum_dictionary.txt` — curated phylum-to-kingdom/superkingdom map
- `TaxoBase.db` — SQLite taxonomy database. The latest version is available at: 

## Setup

You need:
- Perl (v5.26+)
- The following CPAN/Conda modules:
  - `DBI`
  - `DBD::SQLite`
  - `LWP::UserAgent`
  - `JSON`
  - `XML::Simple`
  - `URI::Escape`
  - `List::MoreUtils`

## Running

```bash
perl bin/main.pl your_taxonomy_table.tsv
