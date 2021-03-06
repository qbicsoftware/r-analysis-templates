library(gProfileR)
library(ggplot2)
library(reshape2)
library(pheatmap)
library(pathview)
library(AnnotationDbi)

# Need to load library for your species
library(org.Mm.eg.db)


outdir <- "gProfileR_16H"
path_contrasts <- "DESeq2/results_time_16H/DE_genes_contrasts/"
path_norm_counts <- "DESeq2/results_time_16H/count_tables/rlog_transformed.read.counts.tsv"
metadata_path <- "DESeq2/metadata/QSFAN_sample_preparations.tsv"
final_tab_path <- "DESeq2/results_time_16H/final/final_list_DESeq2.tsv"
contrast_files <- list.files(path=path_contrasts)
norm_counts <- read.table(file = path_norm_counts, header = T, row.names = 1, sep = "\t", quote = "")
metadata <- read.table(file=metadata_path, sep = "\t", header = T, quote="")
metadata <- metadata[which(metadata$Condition..extraction_time == "16H"),]
final_tab <- read.table(file = final_tab_path, header=T, sep = "\t", quote ="")
gene_id <- final_tab[,c("gene_name", "ID")]


#Search params
organism <- "mmusculus"
short_organism_name <- "mmu"
datasources <- c("KEGG","REAC")
min_set_size <- 1
max_set_size <- 500
min_isect_size <- 1



# Create output directory
dir.create(outdir)
pathway_heatmaps_dir <- "pathway_heatmaps"

# Set theme for graphs
theme_set(theme_classic())

for (file in contrast_files){
  #Reading DE genes list
  fname <- tools::file_path_sans_ext(basename(file))
  
  dir.create(paste(outdir, fname, sep="/"))
  dir.create(paste(outdir, fname, pathway_heatmaps_dir, sep="/"))
  
  DE_genes <- read.csv(file = paste0(path_contrasts, file), sep="\t", header = T)
  q = as.character(DE_genes$Ensembl_ID)
  
 
  #gprofiler query
  path_enrich <- gprofiler(query = q, organism=organism, 
                           significant = T, correction_method = "fdr",
                           min_set_size = min_set_size, max_set_size = max_set_size, min_isect_size = min_isect_size,
                           src_filter = datasources)
  
  if (nrow(path_enrich) > 0){
    path_enrich$original.query.size <- rep(length(q), nrow(path_enrich))
  }
  write.table(path_enrich, file = paste0(outdir, "/", fname, "/",fname, "_pathway_enrichment_results.tsv"), sep = "\t", quote = F, col.names = T, row.names = F )
  
  # Printing numbers
  print("------------------------------------")
  print(fname)
  print("Number of genes in query:")
  print(length(DE_genes$Ensembl_ID))
  print("Number of pathways found:")
  print(summary(as.factor(path_enrich$domain)))
  print("------------------------------------")
  
  if (nrow(path_enrich) > 0){ #if there are enriched pathways
    # Splitting results according to tools
    res <- split(path_enrich, path_enrich$domain)
    for (df in res){
      db_source <- df$domain[1]
      print(db_source)
      
      df$short_name <- sapply(df$term.name, substr, start=1, stop=50)
      # Plotting results for df
      df_subset <- data.frame(Pathway_name = df$short_name, Query = df$overlap.size, Pathway = df$term.size, Fraction = (df$overlap.size / df$term.size), Pval = df$p.value)
      #df_plot <- melt(data = df_subset, value.name = "N_genes", id.vars = "Pathway_name")
      #df_plot$variable <- as.factor(df_plot$variable, levels=c("Query", "Pathway"))
      p <- ggplot(df_subset, aes(x=reorder(Pathway_name, Fraction), y=Fraction)) +
        geom_bar(aes(fill=Pval), stat="identity", width = 0.7) +
        geom_text(aes(label=paste0(df_subset$Query, "/", df_subset$Pathway)), vjust=0.4, hjust=-0.5, size=3) +
        coord_flip() +
        scale_y_continuous(limits = c(0.00, 1.00)) +
        scale_fill_continuous(high = "#132B43", low = "#56B1F7") +
        ggtitle("Enriched pathways") +
        xlab("") + ylab("Gene fraction (Query / Pathway)")
      ggsave(p, filename = paste0(outdir, "/", fname, "/", fname, "_", db_source, "_pathway_enrichment_plot.pdf"), device = "pdf", height = 2+0.5*nrow(df_subset), units = "cm", limitsize=F)
      ggsave(p, filename = paste0(outdir, "/", fname, "/", fname,"_", db_source, "_pathway_enrichment_plot.png"), device = "png", height = 2+0.5*nrow(df_subset), units = "cm", dpi = 300, limitsize=F)
      
      # Plotting heatmaps and pathways for all pathways
      print("Plotting heatmaps...")
      if (nrow(df) <= 100 & nrow(df) > 0) {
        conditions <- grepl("Condition", colnames(metadata))
        metadata_cond <- as.data.frame(metadata[,conditions])
        metadata_cond_name <- apply(metadata_cond,1,paste, collapse = "_")
        metadata$cond_name <- metadata_cond_name
        metadata_name <- metadata[,c("QBiC.Code", "cond_name")]
        row.names(metadata_cond) <- apply(metadata_name,1,paste, collapse = "_")
        
        for (i in c(1:nrow(df))){
          pathway <- df[i,]
          gene_list <- unlist(strsplit(pathway$intersection, ","))
          mat <- norm_counts[gene_list, ]
          
          png(filename = paste(outdir, "/",fname, "/", pathway_heatmaps_dir, "/", "Heatmap_normalized_counts_", pathway$domain, "_", pathway$term.id, "_",fname, ".png", sep=""), width = 2500, height = 3000, res = 300)
          pheatmap(mat = mat, annotation_col = metadata_cond, main = paste(pathway$short_name, "(",pathway$domain,")",sep=" "), scale = "row", cluster_cols = F, cluster_rows = F )
          dev.off()
        
          # Plotting pathway view only for kegg pathways
          if (pathway$domain == "keg"){
            pathway_kegg <- sapply(pathway$term.id, function(x) paste0(short_organism_name, unlist(strsplit(as.character(x), ":"))[2]))

            gene.data = DE_genes
            gene.data.subset = gene.data[gene.data$Ensembl_ID %in% gene_list, c("Ensembl_ID","log2FoldChange")]
            
            entrez_ids = mapIds(org.Mm.eg.db, keys=as.character(gene.data.subset$Ensembl_ID), column = "ENTREZID", keytype="ENSEMBL", multiVals="first")
            
            gene.data.subset <- gene.data.subset[!(is.na(entrez_ids)),]
            row.names(gene.data.subset) <- entrez_ids[!is.na(entrez_ids)]
            
            gene.data.subset$Ensembl_ID <- NULL
            pathview(gene.data  = gene.data.subset,
                    pathway.id = pathway_kegg,
                    species    = short_organism_name,
                    out.suffix=paste(fname,sep="_"))
          }
        }
      }
    }
  }
}



