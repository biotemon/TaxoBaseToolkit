# --- First steps --- #
# Make sure to run first
# perl bin/main.pl your_input_file.tsv
# Previous line will generate a file like your_input_file_taxonomyXcounts.txt
# Assuming you change the name to taxonomy_input.tsv
# mv your_input_file_taxonomyXcounts.txt taxonomy_input.tsv

# --- User-defined parameters (an example) --- #
#INPUT_FILE="taxonomy_input.tsv"
#THRESHOLD=4
#WORKDIR="$(pwd)"  # Use the current working directory
#SAMPLE_NAMES='"LN_nm0", "LN1", "LN2", "LN_nm10", "LN4", "LN5", "LN6", "LN_met10", "LN7", "LN8", "LN9"'

# --- Inject values into a temp R script --- #
#sed -e "s|{{INPUT_FILE}}|$INPUT_FILE|g" \
#    -e "s|{{THRESHOLD}}|$THRESHOLD|g" \
#    -e "s|{{WORKDIR}}|$WORKDIR|g" \
#    -e "s|{{SAMPLE_NAMES}}|$SAMPLE_NAMES|g" \
#    plot_community_structure_template.R > plot_community_structure.R

# --- Run the R script --- #
#Rscript plot_community_structure.R
