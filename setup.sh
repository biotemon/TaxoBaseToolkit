#!/bin/bash

echo "📦 Setting up TaxoBaseToolkit..."

# 1. Create conda environment
echo "⏳ Creating Conda environment 'taxobase_env'..."
conda create -y -n taxobase_env perl perl-dbi perl-dbd-sqlite perl-uri perl-json perl-libwww-perl perl-xml-simple perl-list-moreutils

echo "✅ Conda environment created!"
echo "👉 To activate it now: conda activate taxobase_env"
echo

# 2. Prompt for user config
read -p "📧 Enter your NCBI email: " user_email
read -p "🔑 Enter your NCBI API key: " user_apikey

# 3. Download the DB

read -p "📂 Enter full path to the folder where TaxoBase.db should be stored: " taxobase_dir

# Expand ~ and check directory exists
taxobase_dir=$(eval echo "$taxobase_dir")
if [ ! -d "$taxobase_dir" ]; then
    echo "❌ Directory does not exist: $taxobase_dir"
    exit 1
fi

taxobase_path="$taxobase_dir/TaxoBase.db"

echo "⏬ Downloading latest TaxoBase.db from OSF..."
wget -q https://osf.io/y3v67/download -O "$taxobase_path"


if [ $? -ne 0 ]; then
  echo "❌ Download failed. Please check your internet connection or URL."
  exit 1
fi

echo "✅ Downloaded TaxoBase.db to: $taxobase_path"
echo

# Ensure log folder exists
mkdir -p logs
touch logs/not_found_taxa.log logs/mismatch_taxa.tsv


# 4. Update main.pl
echo "🔧 Updating database path in main.pl..."
sed -i.bak "s|SET_YOUR_TAXOBASE_DB|$taxobase_path|" bin/main.pl

# 5. Update ncbi_agent.pl
echo "🔧 Inserting user email and API key into ncbi_agent.pl..."
sed -i.bak "s|SET_YOUR_EMAIL|$user_email|" bin/ncbi_agent.pl
sed -i.bak "s|SET_YOUR_APIKEY|$user_apikey|" bin/ncbi_agent.pl

# Clean up backup files
rm bin/*.bak

echo
echo "✅ Setup complete! You can now run:"
echo
echo "   conda activate taxobase_env"
echo "   perl bin/main.pl my_input.tsv"
echo
