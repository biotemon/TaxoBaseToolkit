# TaxoBase Toolkit

This toolkit provides a portable pipeline to normalize and annotate microbial and viral taxonomies using a local SQLite database and the NCBI taxonomy API.


## Components

- `main.pl` — main pipeline script
- `ncbi_agent.pl` — supplemental taxonomy fetcher
- `phylum_dictionary.txt` — curated phylum-to-kingdom/superkingdom map
- `TaxoBase.db` — SQLite taxonomy database. The latest version is available at:
- `plot_community_structure_template.R` - R script to perform hierarchical taxonomy coalescence and visualization


## 🚀 Quickstart

### 1. Clone the repository

```bash
git clone https://github.com/biotemon/TaxoBaseToolkit.git
cd TaxoBaseToolkit
```


### 2. Run the setup script

```bash
bash setup.up
```

This will:

- Create a Conda environment with required Perl modules

- Prompt for your NCBI email and API key

- Download the latest TaxoBase.db to the path you specify

- Patch `test.pl` and `ncbi_agent.pl` with your values


## 🔧 Dependencies

Installed automatically by `setup.sh via Conda:
- Perl (v5.26+)
- The following CPAN/Conda modules:
  - `DBI`
  - `DBD::SQLite`
  - `LWP::UserAgent`
  - `JSON`
  - `XML::Simple`
  - `URI::Escape`
  - `List::MoreUtils`


## 📁 Repository Structure

```graphql
TaxoBaseToolkit/
├── bin/
│   ├── main.pl               # Main taxonomy expansion pipeline
│   ├── ncbi_agent.pl         # NCBI query helper script
│   └── plot_community_structure_template.R     # Use the output of main.pl to perform hierarchical coalescence and visualization 
├── scripts/
│   └── run_plot_community_structure.sh
├── data/
│   └── phylum_dictionary.txt # Phylum-to-kingdom/superkingdom map
├── db/
│   └── TaxoBase.db           # Downloaded SQLite taxonomy database
├── logs/                     # Stores logs like not_found_taxa.log
├── setup.sh                  # One-time setup and configuration
├── README.md
└── .gitignore
```


## 🧪 How to Use

After the setup:

```bash
conda activate taxobase_env
perl bin/main.pl path/to/your_input_table.tsv
bash scripts/run_plot_community_structure.sh
```


## 📬 NCBI Usage

The first time you run setup.sh, you’ll be prompted for:

- Your NCBI-registered email address

- An optional NCBI API key (get it from https://www.ncbi.nlm.nih.gov/account/settings/)

These will be embedded in `bin/ncbi_agent.pl` for compliant, high-throughput access.


## 📄 License

MIT License. © 2025 Tito Montenegro.
