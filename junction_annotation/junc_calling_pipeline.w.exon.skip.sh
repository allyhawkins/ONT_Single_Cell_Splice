#!/usr/bin/env bash
#SBATCH --job-name=junc_annot
#SBATCH --partition=pe2
#SBATCH --mail-type=NONE
#SBATCH --mem=80g
#SBATCH --output=junc_annot_stdout_%j.log

##Pipeline to go from ONT Bam file (from SiCeLoRe output) --> junction:cell annotated matrix

##Format: bash junc_calling_pipeline.sh path/to/main_output_folder sample_name path/to/run_files
##Example: sbatch junc_calling_pipeline.sh /gpfs/commons/groups/landau_lab/SF3B1_splice_project/6.Junction_analysis_files/2.ONT_juncs CH259 run_files 

# output_location
# input_bam 
# sample 
# scripts_dir
# make_refs
# refs_dir
# leafcutter_dir 
# gtf

# set defaults 
#scripts_dir="/gpfs/commons/groups/landau_lab/mariela/tools/ONT-sc-splice/junction_annotation"


# grab arguments from command line
while [ $# -gt 0 ]; do
    if [[ $1 == *'--'* ]]; then
        v="${1/--/}"
        declare $v="$2"
        echo "${v}: ${2}" 
    fi
    shift
done
make_refs=false 

leafcutter_dir="/gpfs/commons/groups/landau_lab/SF3B1_splice_project/gmullokandov/software/leafcutter"
gtf="$refs_dir"/gencode.v31.basic.annotation.gtf
refs_dir="${scripts_dir}/annotation_reference/"

#module load python/3.5.1

##### ----------------------- Generate Intron/3p/5p databases from GTF file (only need to do this once)  ----------------------- #####

# if make_refs set to true then 
if ${make_refs} ; then
    mkdir -p $output_refs
    $leafcutter_dir/leafviz/gtf2leafcutter.pl \
      -o "$refs_dir" \
      $gtf
fi

annotation_code=${refs_dir}

##### ----------------------- Run the python junction calling script ----------------------- #####

#Format: python script_to_run path/to/input/bam path_to_output_file
echo "starting junction calling" 

cd $output_location
mkdir -p leafcutter_outputs
cd ./leafcutter_outputs

python "$scripts_dir"/bin/count_introns_ONT.py \
  $input_bam \
  "$sample"_counts_sc_txt.gz
echo "junction calling done" 

##### ----------------------- Run the pre-processing scripts ----------------------- #####

echo "Running pre-processing scripts"

#module load anaconda3
#source /nfs/sw/anaconda3/anaconda3-10.19/etc/profile.d/conda.sh
#conda activate /gpfs/commons/home/pchamely/.conda/envs/RenvForKnowlesPCA
mkdir -p "$sample"_output

#Format: Rscript junc_calling_script.R path/to/*_counts_sc_txt.gz path/to/output_folder patient_ID path/to/annotation_code/prefix"

Rscript "$scripts_dir"/bin/junc_calling_script.R \
  "$sample"_counts_sc_txt.gz \
  "$sample"_output \
  "$sample" \
  "${annotation_code}/leafviz"

echo "Done" 

##### ----------------------- Run annotation script  ----------------------- #####
#conda deactivate
#export PATH="/gpfs/commons/home/lkluegel/miniconda3/bin:$PATH"

cp "${annotation_code}/leafviz_all_introns.bed.gz" "${sample}_output/"
gunzip "${sample}_output/leafviz_all_introns.bed.gz"

#clean the intron.bed file for exon skipping
python ${scripts_dir}/bin/intron_bed_cleaner.py \
  "${sample}_output/leafviz_all_introns.bed" \
  "${sample}_output/leafviz_all_introns_cleaned.bed"

# run annotation script with exon skipping
python ${scripts_dir}/bin/new_annotator_with_skipping.py \
  "${output_location}/leafcutter_outputs/" \
  "${sample}_output/${sample}_all.introns.info.txt" \
  "${sample}_output/leafviz_all_introns.bed" \
  "${sample}_output/leafviz_all_introns_cleaned.bed" ONT \
  "${sample}_all.introns.info.w.primaryAnnotations.exonSkipping.txt"
