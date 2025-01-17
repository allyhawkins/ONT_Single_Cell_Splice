<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Single Cell Splicing Analysis of ONT Reads](#single-cell-splicing-analysis-of-ont-reads)
  - [Requirements](#requirements)
  - [Reference files and general setup](#reference-files-and-general-setup)
  - [GoT-Splice Pipeline overview](#got-splice-pipeline-overview)
    - [Junction Calling in Single Cells](#junction-calling-in-single-cells)
    - [Annotation of Junctions](#annotation-of-junctions)
    - [Differential Transcript Usage](#differential-transcript-usage)
      - [Option A: Individual Samples](#option-a-individual-samples)
      - [Option B: Combine Samples](#option-b-combine-samples)
      - [Option C: Within Cell Types/ Clusters](#option-c-within-cell-types-clusters)
  - [Running the full GoT-Splice pipeline](#running-the-full-got-splice-pipeline)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


# Single Cell Splicing Analysis of ONT Reads

These tools allow for identification of differentially spliced transcripts in single cells from long read data. Full length cDNA produced from the 10X 3' single cell RNA sequencing kit is sequenced using oxford nanopore technologies (ONT) to get reads corresponding to full length transcripts. Prior to use of this pipeline, reads are aligned and cell barcodes and UMI's are identified in each read using the previously published pipeline [SiCeLoRe](https://www.nature.com/articles/s41467-020-17800-6). A tagged bam file containing tags for cell barcodes and UMI are then processed using a similar method to [leafcutter](https://davidaknowles.github.io/leafcutter/) to call intron junctions found in each cell. Intron junctions are annotated as either alternative 3' or alternative 5' prior to differential transcript usage. 

Additionally, genotype status of mutation of interest (in this case SF3B1 in patients with myeloid displastic syndrome) was determined using the previously published method, [GoT](https://www.nature.com/articles/s41586-019-1367-0). Differential transcript usage can then be determined within each sample, comparing mutant and wild type cells, and can be further broken down by cell type. We also allow here an option to integrate across multiple single cell samples.

## Requirements 
- [SiCeLoRe](https://github.com/ucagenomix/sicelore)
- [minimap2](https://github.com/lh3/minimap2)
- [samtools](http://www.htslib.org/)
- [racon](https://github.com/isovic/racon)
- Java 1.9 or higher

## Reference files and general setup

You will need to provide the following reference files: 

1. Minimap2 reference index in the `mmi` format.
In the below example `ref.fa` is the input fasta sequence and `ref.mmi` is the output index that will be used for mapping.

```
minimap2 -d ref.mmi ref.fa # indexing
```

2. Reference junctions bed file - To account for the high error rate in ONT, we utilize a reference of splice junctions identified from short read sequencing from a library without a splicing mutation. 
This is highly recommended as to identify the most accurate splice junction calls. 
Using the [splice aware alignment with STAR](https://github.com/alexdobin/STAR), we created a reference `.bed` file. 

3. Complementary short read data must be processed through [Cell Ranger](https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/latest/what-is-cell-ranger) prior to using this pipeline to obtain the `posssorted_bam.bam` and `outs/filtered_feature_bc_matrix/barcodes.tsv` file. 

4. Short read data must also be processed through [IronThrone](https://github.com/dan-landau/IronThrone-GoT) to obtain genotyping results. 
A genotyping table containing the following columns is required: 

## GoT-Splice Pipeline overview 

The GoT-Splice pipeline has three large steps, CB/UMI calling in long reads using SiCeLoRe, junction calling, and differential transcript usage. 
Currently, junction calling and differential transcript usage are two separate workflows that can be run independently, or they can be run as one larger pipeline within the GoT-splice workflow where SiCeLoRe is performed first prior to  junction calling and differential transcript usage. 

To run the entire pipeline as is, see the below section on [Running the full GoT Splice pipeline.](#running-the-full-got-splice-pipeline)
However, the current pipeline is set up to use a computing environment that uses slurm and requires altering the queue names. 
For all other computing environments, we recommend first running [SiCeLoRe following their user guidelines](https://github.com/ucagenomix/sicelore). 
After which the output from SiCeLoRe can be used as input to junction calling and then differential transcript usage.

### Junction Calling in Single Cells

Junction calling is modelled after methods described in leafcutter, originally developed for identifying junctions in short read RNA-sequencing data. 
All scripts needed for junction calling can be found in [`junction_annotation/bin`](./junction_annotation/bin/).

1. Before calling junctions on your own sample, you must generate your own annotation reference files. 
This can be done on your own by using the function `gtf2leafcutter.pl()` from [leafcutter](https://davidaknowles.github.io/leafcutter/index.html). 
Or you may use our annotation references found in the [`junction_annotation/annotation_reference`](./junction_annotation/annotation_reference/) folder generated using Hg38. 

2. Count junctions. Input bam must be bam file with cell barcode tags (BC) and UMI tags (U8) 
```
python count_introns_ONT.py \
  <path to bam output from SiCeLoRe> \
  <path to output file>
```
3. Creating metadata table and adding junction information to counts matrix. This step also includes the assigning of cluster IDs. A Cluster ID is an ID that is unique to all junctions that have the same 5p or the same 3p end. Junctions within the same cluster represent a group of junctions that have been alternatively spliced. 
```
Rscript junc_calling_script.R \
  <path to output folder> \
  <sample_ID> \
  <path to annotation_reference>
```
Final ouptput: Counts matrix with each row as a junction and each column as a cell, metadata containing junction information, including gene, transcript ID, and chromosomal location. 

### Annotation of Junctions

Annotation of junctions identified in sample. 
Here the reference gtf is used to classify each 5' and 3' end of the intron. 
Output will add on additional columns to the metadata table including startClass and endClass, classifying the junction ends as the canonical (main) or alternative (not_main_3_prime/not_main_5_prime) end. 
Events will also be classified as exon skipping events or alternative splicing events. 
```
python new_annotator_with_skipping.py \
  <path to junction calling outputs> \
  <input datafile (output from previous step)> \
  <bed file output from intron junction calling> \
  <output file name> 
```

To run the junction annotation pipeline alltogether run the following: 

:warning: This is a shell script that is set up to run in a slurm environment with queues named `bigmem` and `pe2`. 
Note that you will need up to 200 GB of memory to run this pipeline and the front matter of the shell script should be adjusted for your slurm environment.

```
sbatch junction_annotation/junc_calling_pipeline.w.exon.skip.sh \
  --output_location <path to junction calling outputs> \
  --input_bam <path to bam output from SiCeLoRe> \
  --sample <sample_ID> \
  --scripts_dir <path to junction annotation folder in GoT splice repo>

```

By default the junction annotation will run without creating new annotation files. 
If you would like to run it with creating new annotation files you can run it using the `--make_refs true` option. 
You will also need to provide a directory to store the annotation files and a gtf file from which to create the annotation files. 
You will also need to have [leafcutter](https://davidaknowles.github.io/leafcutter/index.html) downloaded and provide the path to the leafcutter directory.

```
sbatch junction_annotation/junc_calling_pipeline.w.exon.skip.sh \
  --output_location <path to junction calling outputs> \
  --input_bam <path to bam output from SiCeLoRe> \
  --sample <sample_ID> \
  --scripts_dir <path to junction annotation folder in GoT splice repo> \
  --make_refs true \
  --refs_dir <path to directory to output the reference files> \
  --leafcutter_dir <path to leafcutter> \
  --gtf <path to input gtf file> 
```

### Differential Transcript Usage

All scripts needed for differential transcript usage can be found in [`diff_transcript_usage/bin`](./diff_transcript_usage/bin/).

1. Strand adjustment of metadata file. 
Adds in columns to assign start/end as five prime or three prime ends of the gene for annotations. 
The output is an uypdated metadata file with new columns added, `fivep_class` and `threep_class`. 

```
Rscript strand_adjustment.R \
  <metadata> \
  <path/to/output>
```

#### Option A: Individual Samples

2. Run Differential transcript usage analysis. 
This requires the strand adjusted metadata matrix, full counts matrix from intron junction calling, and a table with cell barcodes, genotype information, and cell type assignment (produced from short read data analysis using GoT). 
By default, junctions with no alternative sites and less than 5 total reads will be filtered out prior to calculating an odds ratio for each junction in comparison to all other junctions with the same three prime or five prime end. 
To adjust the minimum reads, use the `--min_reads` argument. 
Genotype assignments are then permuted x number of times (we recommend doing a test with 100-1000 but using at least 100,000 for making any final conclusions) and odds ratios are recalculated before determining the likelihood of the observed odds ratio being statistically significant. 
Number of permutations are dictated by the `nperm` argument.
A final table for both `Alt_5P` and `Alt_3P` is output along with the `log(odds ratio)` for each junction and total observed reads across mutant and wild type cells. 
  
With a high number of junctions, it is likely that this may take a long time to run all clusters at once. 
We recommend splitting by cluster ID and then running for each group of smaller clusters a modified version that we have provided. 
See example below along with an example of how to run and submit on a slurm cluster in the examples folder. 

```
Rscript split_clusters_v2.R \
  --counts <counts> \
  --genotype_file <genotype> \
  --metadata <strand adjusted metadata> \
  --pattern <pattern/ sample ID added to cell barcodes> \
  --output_dir <path/to/output>

Rscript split_JuncPermute_LogOR_perm_within_celltype_5p_3p.r \
  --split <path to split files> \
  --genotype_file <genotype> \
  --num_perm <number of permtuations> \
  --pattern <pattern> \
  --output_dir <output directory> \
  --output_file <output file name> 
  
Rscript merge_final_output_ind_patient.R \
  <path to split 0utput> \
  <path to metadata> \
  <path to output>

```

**Note:** To run the full differential transcript usage workflow on a slurm cluster, use the following: 

```
sbatch diff_transcript_pipeline.sh \
  --output_dir <path to output dir> \
  --scripts_dir <path to junction annotation folder in GoT splice repo> \
  --metadata <path to metadata (output from junction annotation)> \
  --counts <path to counts matrix> \
  --genotype_info <path to genotype file> \
  --pattern <pattern> \
  --sample_name <sample name> \
  --nperm 100000 \
  --min_reads 5

```

#### Option B: Combine Samples

If you have multiple samples that you would like to compare and look for differential transcript usage across all samples, we have also implemented a way to integrate the same analysis described above across our samples. Here, we ony keep clusters that are found in all samples and again only junctions that have n > 5 reads by default. 
The output includes the individual odds ratio for each sample for each junction as well as a weighted odds ratio based on total cells found in each sample. 
There will be one p-value reported for each junction corresponding to the significance that this junction is differentially used across all samples. 
There is no minimum or maximum number of samples needed.
Here you will need to move all files for all patients into one folder - i.e. all counts matrices should be in one folder and all genotype information should be in another folder. 
Again, to increase speed, we suggest that we split across clusters so have provided the scripts to do so. 

```
Rscript create_combined_metadata.R \
  <path to metadata> \
  <path to output> \
  <sample names> 

Rscript split_clusters_comb_patient_merge_counts_1WT.R \
  --counts <path to folder with counts> \
  --genotype_file <path to folder with genotype> \
  --metadata <path to combined metadata> \
  --output_dir <path to output> \
  --sample_names <sample names> \
  --pattern <pattern/unique identifiers on cell barcodes> \
  --min_reads 5 

Rscript split_JuncPermute_LogOR_combined_patient_within_celltype.R \
  <path to split files> \
  <path to genotype> \
  <number of permutations> \
  <path to output> \
  <output file name>
  
Rscript merge_final_output_comb_patient.R \
  <path to outputs> \
  <path to metadata> \
  <sample names> \
  <path to output>
```

#### Option C: Within Cell Types/ Clusters

Finally, using information defined from short read illumina sequencing, you can identify differentially used transcripts across cell types. 
Here, we integrate across samples and across cell types in order to identify key transcripts that are differentially spliced between mutant and wild type cells in various cell types. 
Permutations happen within each sample and within each cell type. 
The output table contains a combined table with weighted odds ratio for each junction found in each cell type with one p-value being reported for the likelihood that junction is significantly differentially used in each cell type. 
This can also be applied to clusters within a sample and does not need to be within cell types. 

To run individual patient within each cell type, run the following: 

```
Rscript split_JuncPermute_ind_patient_mut_wt_all_celltypes.R \
  <path to split files> \
  <path to genotype> \
  <number of permutations> \
  <path to output> \
  <output file name>

Rscript merge_ind_celltype_output.R \
  <path to split output dir> \
  <path to metadata> \
  <path to genotype file> \
  <path to final output>
```

To run combined patient within each cell type, run the following: 

```
Rscript JuncPermute_LogOR_combined_patient_celltype.R \
  <path to counts> \
  <path to genotype> \
  <path to metadata> \
  <number of permutations> \
  <path to output>

Rscript merge_final_output_comb_patient_merge_counts.R \
  <path to split output dir> \
  <path to metadata> \
  <path to final output>

```

## Running the full GoT-Splice pipeline

To run as one combined pipeline on slurm cluster, use `splice_pipeline.sh`. 

```
sbatch splice_pipeline.sh \
  --fastq <full path to fastq, gzipped> \
  --short_read_files <directory to outs folder from Cell Ranger> \
  --sample_name <unique sample identifier> \
  --genotype_info <genotype_table> \
  --output_dir <directory to write all output files> \
  --pattern <pattern/sample ID on cell barcodes from integrated objects> \
  --ref_genome <path to reference minimap2 index> \
  --ref_junc_bed <path to reference bed file for splice junction correction> \
  --sicelore_dir <path to sicelore directory> \
  --minimap_dir <path to minimap2 directory>
```

:warning: This is only set up to run on a slurm HPC. 
It also assumes queue names of `pe2` and `bigmem`. 
If other queue names are used by your HPC those should be changed before running the workflow. 

This also relies on loading modules with the following commands: 

```
source /etc/profile.d/modules.sh
module load java/1.9
module load samtools
module load racon
```
These lines should either be changed or commented out before running and modules should be load in the correct format for your HPC. 

## Updated version - 2024

To facilitate testing the software, we have included the [ont_sc_splice.yml](ont_sc_splice.yml) file that allows for the creation of a conda environment containing the required software. This can be done by using the following command: 

```
conda env create -f ont_sc_splice.yml 
```

Additionally, we provide a small example of the splicing-analysis part of the pipeline located in the [minimal_example](minimal_example) folder. This assumes that the files have been processed through SiCeLoRe. The pipeline then can be invoked by running the `splicing_pipeline_after_sicelore.sh` and requires as input a folder with the following structure: 

```
.
└── output_files
    ├── sicelore_outputs
        ├── <unique sample identifier>_consensus.sorted.tags.GE.bam
        └── <unique sample identifier>_consensus.sorted.tags.GE.bam.bai

```

As well as the genotype annotated file which should contain: 

  - the genotype column named `Genotype_1UMI`
  - the `Cell.Assignment` colum with the defined cell types
  - the cell barcodes as row names

