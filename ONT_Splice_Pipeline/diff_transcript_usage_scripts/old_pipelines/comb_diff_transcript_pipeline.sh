#!/bin/bash

#SBATCH --mem=100g
#SBATCH --partition=bigmem,pe2
#SBATCH --cpus-per-task=10

module load R/3.6.0


### arguments input for this file

workdir=$1
run_files=$2
pattern=$3
patients=$4
nperm=$5
sample_name=$6


counts="$workdir"/1.Counts_matrix
genotype="$workdir"/2.Genotype_info
metadata="$workdir"/3.Annotated_metadata

## input folder should have three folders
# 1.Counts_matrix - all counts matrix for all patients being combined
# 2.Genotype_info - all genotype tables for all patients
# 3.Annotated_metadata - strand adjusted metadata for all patients 

###############################################################
######## Step 1: Combine Metadata to make Common Cluster ID's ############
### Input: metadata output from leafcutter annotation for all patients
### Input: path to output files/ working directory 
### Output: Combined output

## format: Rscript strand_adjustment.R <metadata> <output directory> 

###############################################################

cd $workdir 
mkdir diff_transcript_combined_output
cd ./diff_transcript_combined_output
mkdir combined_metadata

Rscript "$run_files"/bin/create_combined_metadata.R $metadata "$workdir"/diff_transcript_combined_output/combined_metadata $patients


##############################################################
######### Step 2: Split clusters for differential transcript usage
### Input: full counts matrix from leafcutter junction calling
### Input: Genotype matrix
### Input: Strand adjusted metadata
### Input: Pattern (i.e. barcode pattern, "_1", "_2", or "_3")
### Input: Output directory 

## format: Rscript split_clusters_v2.R <counts> <genotype> <metadata> <pattern> <output>

###############################################################

mkdir split_cluster_files
cd ./split_cluster_files

for i in {1..250}
do 
mkdir split_"$i"
mkdir split_"$i"/three_prime
mkdir split_"$i"/five_prime
mkdir split_"$i"/three_prime/counts_files
mkdir split_"$i"/three_prime/data_tables
mkdir split_"$i"/five_prime/counts_files
mkdir split_"$i"/five_prime/data_tables
done

Rscript "$run_files"/bin/split_clusters_combined_patient_v2_MDS_treated.R $counts $genotype $metadata "$workdir"/diff_transcript_combined_output/split_cluster_files $patients $pattern

###########################################################
######## Step 3: Batch submit each split cluster for differential analysis
### Input: path to split files 
### Input: path to genotype matrix 
### Input: Number of permutations
### Input: output directory 
### Input: output file name 
### output: differential transcript table for 3p and 5p in two separate folders

## format: sbatch run_split_perm_within_celltype_5p_3p.sh <path to split files> <genotype> <nperm> <output.dir> <output.file> 

###########################################################

cd ..
mkdir split_cluster_output
mkdir split_cluster_output/alt_three_prime
mkdir split_cluster_output/alt_five_prime
mkdir logs

permute_jobids=()
for i in {1..250}; do
permute_jobids+=($(sbatch --job-name="$sample_name" "$run_files"/bin/run_split_permute_comb_within_celltype_logOR.sh "$workdir"/diff_transcript_combined_output/split_cluster_files/split_"$i" $genotype $nperm $patients "$workdir"/diff_transcript_combined_output/split_cluster_output output_"$i" "$run_files"/bin))
done 

###########################################################
####### Step 4: Merge final output into one file and merge with all annotation information 
### Input: run_files path 
### Input: outputs directory where all files are stored
### Input: strand adjusted metadata 
### Input: Final outfile 

mkdir merge_final_output

#sbatch "$run_files"/bin/run_merge_output.sh "$run_files"/bin "$workdir"/diff_transcript_output/split_cluster_output "$workdir"/strand_adjusted_metadata/strand_adjusted_metadata.csv "$workdir"/diff_transcript_output/merge_final_output

merge=($(sbatch --dependency=singleton --job-name="$sample_name" "$run_files"/bin/run_merge_combine_output.sh "$run_files"/bin "$workdir"/diff_transcript_combined_output/split_cluster_output "$workdir"/diff_transcript_combined_output/combined_metadata/combined_metadata.csv $patients "$workdir"/diff_transcript_combined_output/merge_final_output))

echo "Done!" 

