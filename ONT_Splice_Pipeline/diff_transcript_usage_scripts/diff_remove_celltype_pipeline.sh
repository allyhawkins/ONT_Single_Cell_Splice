#!/bin/bash

#SBATCH --mem=100g
#SBATCH --partition=bigmem,pe2
#SBATCH --cpus-per-task=10

module load R/3.6.0


### arguments input for this file

workdir=$1
run_files=$2
metadata=$3
counts=$4
genotype=$5
pattern=$6
sample_name=$7
nperm=$8
celltypes=$9 #format is ""HSPC" "MEP"" 

echo $celltypes

###############################################################
######## Step 1: Run Strand Adjustment of Metadata ############
### Input: metadata output from leafcutter annotation 
### Input: path to output files/ working directory 
### Output: Srand adjusted metadata 

## format: Rscript strand_adjustment.R <metadata> <output directory> 

###############################################################

cd $workdir 
#mkdir strand_adjusted_metadata

#Rscript "$run_files"/bin/strand_adjustment.R $metadata "$workdir"/strand_adjusted_metadata

##############################################################
######### Step 2: Split clusters for differential transcript usage
### Input: full counts matrix from leafcutter junction calling
### Input: Genotype matrix
### Input: Strand adjusted metadata
### Input: Pattern (i.e. barcode pattern, "_1", "_2", or "_3")
### Input: Output directory 

## format: Rscript split_clusters_v2.R <counts> <genotype> <metadata> <pattern> <output>

###############################################################

mkdir diff_transcript_output_remove_celltypes
cd ./diff_transcript_output_remove_celltypes

for type in ${celltypes[*]};
do 
	mkdir "$type"
	cd ./"$type"
	
	mkdir split_cluster_files
	cd ./split_cluster_files

	for i in {1..1000}
	do 
	mkdir split_"$i"
	mkdir split_"$i"/three_prime
	mkdir split_"$i"/five_prime
	mkdir split_"$i"/three_prime/counts_files
	mkdir split_"$i"/three_prime/data_tables
	mkdir split_"$i"/five_prime/counts_files
	mkdir split_"$i"/five_prime/data_tables
	done

	grep -v "$type" $genotype > "$workdir"/diff_transcript_output_remove_celltypes/"$type"/"$type"_genotype_table.txt
        celltype_genotype="$workdir"/diff_transcript_output_remove_celltypes/"$type"/"$type"_genotype_table.txt 

	Rscript "$run_files"/bin/split_clusters_v2.R $counts $celltype_genotype "$workdir"/strand_adjusted_metadata/strand_adjusted_metadata.csv $pattern "$workdir"/diff_transcript_output_remove_celltypes/"$type"/split_cluster_files
 

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
	for i in {1..1000}; do
	permute_jobids+=($(sbatch --job-name="$sample_name" "$run_files"/bin/run_split_perm_within_celltype_5p_3p.sh "$workdir"/diff_transcript_output_remove_celltypes/"$type"/split_cluster_files/split_"$i" $celltype_genotype $nperm $pattern "$workdir"/diff_transcript_output_remove_celltypes/"$type"/split_cluster_output output_"$i" "$run_files"/bin))
	done 

###########################################################
####### Step 4: Merge final output into one file and merge with all annotation information 
### Input: run_files path 
### Input: outputs directory where all files are stored
### Input: strand adjusted metadata 
### Input: Final outfile 

	mkdir merge_final_output

#sbatch "$run_files"/bin/run_merge_output.sh "$run_files"/bin "$workdir"/diff_transcript_output_remove_celltypes/"$type"//split_cluster_output "$workdir"/strand_adjusted_metadata/strand_adjusted_metadata.csv "$workdir"/diff_transcript_output/merge_final_output
	merge=($(sbatch --dependency=singleton --job-name="$sample_name" "$run_files"/bin/run_merge_output.sh "$run_files"/bin "$workdir"/diff_transcript_output_remove_celltypes/"$type"/split_cluster_output "$workdir"/strand_adjusted_metadata/strand_adjusted_metadata.csv "$workdir"/diff_transcript_output_remove_celltypes/"$type"/merge_final_output))
cd ..

done

