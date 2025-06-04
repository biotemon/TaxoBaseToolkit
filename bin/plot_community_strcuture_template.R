suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(RColorBrewer)
  library(reshape2)
  library(svglite)
})

# --- Parameters --- #
INPUT_FILE <- "{{INPUT_FILE}}"
THRESHOLD <- {{THRESHOLD}}  # in percent
RANKS <- c("SPECIES", "GENUS", "FAMILY", "ORDER_TAX", "CLASS", "PHYLUM", "KINGDOM", "SUPERKINGDOM")
WORKDIR <- "{{WORKDIR}}"
SAMPLE_NAMES <- c({{SAMPLE_NAMES}})

setwd(WORKDIR)

# --- Output Folder Setup --- #
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
OUTPUT_FOLDER <- file.path(WORKDIR, paste0("TaxoBase_res_", THRESHOLD, "_", timestamp))

# Create the folder if it doesn’t exist
if (!dir.exists(OUTPUT_FOLDER)) {
  dir.create(OUTPUT_FOLDER, recursive = TRUE)
}

# --- Output File Prefix --- #
OUTPUT_PREFIX <- file.path(OUTPUT_FOLDER, paste0("TaxoBase_res_", THRESHOLD))

# --- Load Data --- #
df <- read.delim(INPUT_FILE, stringsAsFactors = FALSE)

# --- Build Initial Matrix by SPECIES --- #
count_df <- df %>%
  group_by(SAMPLE_ID, SPECIES) %>%
  summarise(count = sum(READ_COUNTS), .groups = "drop") %>%
  pivot_wider(names_from = SPECIES, values_from = count, values_fill = 0)

sample_ids <- count_df$SAMPLE_ID
abs_matrix <- as.data.frame(count_df[, -1])
rownames(abs_matrix) <- sample_ids

# --- Build Relative Matrix --- #
rel_matrix <- sweep(abs_matrix, 1, rowSums(abs_matrix), FUN = "/") * 100
abs_matrix <- as.data.frame(abs_matrix)
rel_matrix <- as.data.frame(rel_matrix)

# --- Taxonomy Table --- #
taxonomy <- df %>%
  select(SPECIES, all_of(RANKS[-1])) %>%
  distinct() %>%
  filter(SPECIES != "_")

# --- Recursive Coalescing Function --- #

for (lvl in seq_along(RANKS)[-length(RANKS)]) {
  
  low_taxa <- names(rel_matrix)[apply(rel_matrix, 2, function(col) all(col < THRESHOLD))]
  
  if (length(low_taxa) == 0) break
  
  for (taxon in low_taxa) {
    parent <- taxonomy %>%
      filter(if_any(everything(), ~ . == taxon)) %>%
      pull(RANKS[lvl + 1]) %>%
      unique()
    parent <- parent[!is.na(parent) & parent != ""]
    if (length(parent) == 0 || parent[1] == taxon) next
    parent <- parent[1]
    
    # Create parent column if needed
    if (!(parent %in% colnames(abs_matrix))) {
      rel_matrix[[parent]] <- rep(0, nrow(rel_matrix))
      abs_matrix[[parent]] <- rep(0, nrow(abs_matrix))
    }
    
    abs_matrix[[parent]] <- abs_matrix[[parent]] + abs_matrix[[taxon]]
    abs_matrix[[taxon]] <- NULL
    
  }
  
  rel_matrix <- sweep(abs_matrix, 1, rowSums(abs_matrix), FUN = "/") * 100
  rel_matrix <- as.data.frame(rel_matrix)
  
}

#Next reorder the taxonomy data frame

taxonomy <- taxonomy[order(taxonomy$SUPERKINGDOM, taxonomy$KINGDOM, taxonomy$PHYLUM, taxonomy$CLASS, taxonomy$ORDER_TAX, taxonomy$FAMILY, taxonomy$GENUS, taxonomy$SPECIES), ]
rownames(taxonomy) <- NULL

# Get row number
guide_vec = c() 
for (taxon in colnames(abs_matrix)) {
  x = taxonomy %>% mutate(row_num = row_number()) %>% filter(if_any(everything(), ~ . == taxon)) %>% slice_head(n = 1) %>% pull(row_num)
  guide_vec = c(guide_vec, x)
}

#Reorder abs and rel matrix following taxonomy hierarchy.
names(guide_vec) <- colnames(abs_matrix)
abs_matrix <- abs_matrix[, names(sort(guide_vec))]
rel_matrix <- rel_matrix[, names(sort(guide_vec))]

coalesced <- list()  # or use data.frame() if you expect a data frame structure
coalesced$absolute <- abs_matrix
coalesced$relative <- rel_matrix

# --- Melt Output Tables --- #
rel_df <- cbind(sample_names = rownames(coalesced$relative), coalesced$relative) %>%
  pivot_longer(-sample_names, names_to = "variable", values_to = "value")
abs_df <- cbind(sample_names = rownames(coalesced$absolute), coalesced$absolute) %>%
  pivot_longer(-sample_names, names_to = "variable", values_to = "value")

# --- Save Output --- #
write.csv(rel_df, paste0(OUTPUT_PREFIX, "_relative_melt.csv"), row.names = FALSE)
write.csv(abs_df, paste0(OUTPUT_PREFIX, "_absolute_melt.csv"), row.names = FALSE)

# --- Prepare for Plotting --- #
rel_df <- as.data.frame(coalesced$relative)
abs_df <- as.data.frame(coalesced$absolute)
rel_df <- cbind(sample_names = SAMPLE_NAMES, rel_df)
abs_df <- cbind(sample_names = SAMPLE_NAMES, abs_df)

rel_melt <- melt(rel_df, id.vars = "sample_names")
abs_melt <- melt(abs_df, id.vars = "sample_names")

rel_melt$sample_names <- factor(rel_melt$sample_names, levels = SAMPLE_NAMES)
abs_melt$sample_names <- factor(abs_melt$sample_names, levels = SAMPLE_NAMES)

# --- Plotting Function --- #
plot_stacked_bar <- function(df, ylab, filename_base) {
  taxa_count <- length(unique(df$variable))
  xval = ceiling(taxa_count/6)
  colfuncA <- colorRampPalette(brewer.pal(xval,"Greens"))
  colfuncB <- colorRampPalette(brewer.pal(xval,"Blues"))
  colfuncC <- colorRampPalette(brewer.pal(xval,"YlOrBr"))
  colfuncD <- colorRampPalette(brewer.pal(xval,"Greys"))
  colfuncE <- colorRampPalette(brewer.pal(xval,"Purples"))
  colfuncF <- colorRampPalette(brewer.pal(xval,"Reds"))
  simple_color_vecA <- colfuncA(xval)
  simple_color_vecB <- colfuncB(xval)
  simple_color_vecC <- colfuncC(xval)
  simple_color_vecD <- colfuncD(xval)
  simple_color_vecE <- rev(colfuncE(xval))
  simple_color_vecF <- colfuncF(xval)
  colors <- c(simple_color_vecA,simple_color_vecB,simple_color_vecC,simple_color_vecD,simple_color_vecE,simple_color_vecF)
  
  ggplot(df, aes(x = sample_names, y = value, fill = variable)) +
    geom_bar(stat = "identity", color = "black", size = 0.25) +
    theme_classic() +
    theme(axis.text.x = element_text(angle = 90, hjust = 1),
          text = element_text(size = 10),
          legend.key.height = unit(0.25, "cm")) +
    scale_fill_manual(values = colors) +
    scale_y_continuous(name = ylab, expand = c(0, 0)) +
    guides(fill = guide_legend(ncol = 1)) +
    xlab("Samples") -> p
  
  # Save as PDF
  ggsave(paste0(filename_base, ".pdf"), p, width = 6, height = 6)
  
  # Save as SVG
  ggsave(paste0(filename_base, ".svg"), p, width = 6, height = 6)
}

# --- Generate Plots --- #
plot_stacked_bar(rel_melt, "Relative Abundance (%)", paste0(OUTPUT_PREFIX, "_relative"))
plot_stacked_bar(abs_melt, "Read Counts", paste0(OUTPUT_PREFIX, "_absolute"))
