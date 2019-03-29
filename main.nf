#!/usr/bin/env nextflow 

/*
========================================================================================
                            m6APipe
========================================================================================
 * m6Apipe
 * Homepage / Documentation

 */

/*
 * to be added
 *
 * Authors:
 * Qi Zhao <zhaoqi@sysucc.org.cn>: design and implement the pipeline.
 * Zhu Kaiyu <zhuky5@mail2.sysu.edu.cn>:
 */

//pre-defined functions for render command
//=======================================================================================

def helpMessage() {
    LikelikeUtils.sysucc_ascii()
    log.info"""
    =========================================
     nf-core/m6Apipe v${workflow.manifest.version}
    =========================================
    Usage:

    The typical command for running the pipeline is as follows:

    nextflow path/to/m6APipe/main.nf --readPaths './data/' --designfile -profile standard,docker 

    Mandatory arguments:
      --readPaths                   Path to input data (must be surrounded with quotes)
      --genome                      Name of iGenomes reference
      --designfile                  format:filename,control_or_treated,ip_or_input,tag_id
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: standard, conda, docker, singularity, awsbatch, test
    
    References                      If not specified in the configuration file or you wish to overwrite any of the references.
      --fasta                       Path to Fasta reference
      --gtf                         Path to GTF reference

    Options:
      --inputformat                 fastq.gz;fastq default = fastq
      --singleEnd                   Specifies that the input is single end reads
      --tophat2_index               Path to tophat2 index, eg. "path/to/Tophat2Index/*"
      --hisat2_index                Path to hisat2 index, eg. "path/to/Hisat2Index/*"
      --bwa_index                   Path to bwa index, eg. "path/to/BwaIndex/*"
      --star_index                  Path to star index, eg. "path/to/StarIndex/"
      --skip_qc                     Skip all QC steps                        
      --skip_aligners               Skip all Reads Mapping steps including Star, bwa, tophat2, hisat2
      --skip_expression             Skip all differential expression analysis steps
      --skip_peakCalling            Skip all Peak Calling steps
      --skip_diffpeakCalling        Skip all Differential methylation analysis

    
    Other options:
      --outdir                      The output directory where the results will be saved, defalut = $baseDir/results
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.
      --skip_fastqc                 Skip FastQC
      --skip_rseqc                  Skip RSeQC
      --skip_genebody_coverage      Skip calculating genebody coverage  
      --skip_tophat2                Skip the Tophat2 process of Reads MappingR steps
      --skip_hisat2                 Skip the Hisat2 process of Reads MappingR steps
      --skip_bwa                    Skip the Bwa process of Reads MappingR steps
      --skip_star                   Skip the Star process of Reads MappingR steps
      --skip_cufflinks              Skip the cufflinks process of differential expression analysis steps
      --skip_edger                  Skip the EdgeR process of differential expression analysis steps
      --skip_deseq2                 Skip the deseq2 process of differential expression analysis steps
      --skip_metpeak                Skip the metpeak process of Peak Calling steps
      --skip_macs2                  Skip the macs2 process of Peak Calling steps
      --skip_matk                   Skip the matk process of Peak Calling steps
      --skip_metdiff                Skip the metdiff process of Differential methylation analysis
      --skip_QNB                    Skip the QNB process of Differential methylation analysis
      --skip_diffmatk               Skip the matk process of Differential methylation analysis
 

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

// Show help emssage
if (params.help){
    helpMessage()
    exit 0
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Configurable variables
params.name = false
params.project = false
params.genome = false
params.call = false
params.email = false
params.plaintext_email = false
params.seqCenter = false
params.help = false
unstranded = params.unstranded ? true : false


// Preset trimming options
/*params.pico = false
if (params.pico){
    clip_r1 = 3
    clip_r2 = 0
    three_prime_clip_r1 = 0
    three_prime_clip_r2 = 3
    forward_stranded = true
    reverse_stranded = false
    unstranded = false
}
*/
// Validate inputs

if ( params.fasta ){
    fasta = file(params.fasta)
    if( !fasta.exists() ) exit 1, LikelikeUtils.print_red("Fasta file not found: ${params.fasta}")
}else {
    exit 1, LikelikeUtils.print_red("No reference genome specified!")
}
if( params.gtf ){
    gtf = file ( params.gtf )
    if( !gtf.exists() ) exit 1, LikelikeUtils.print_red("gtf not found: ${params.gtf}")
} else {
    exit 1, LikelikeUtils.print_red("No GTF annotation specified!")
}
if( params.designfile ) {
    designfile = file(params.designfile)
    if( !designfile.exists() ) exit 1, LikelikeUtils.print_red("Design file not found: ${params.designfile}")
}else{
    exit 1, LikelikeUtils.print_red("No Design file specified!")
}
if( params.TREATED_SITUATION_STARTPOINT ){
    TREATED_SITUATION_STARTPOINT = params.TREATED_SITUATION_STARTPOINT
}else{
    exit 1, LikelikeUtils.print_red("TREATED_SITUATION_STARTPOINT must greater than or equal to 1!")
}

// Validate the params of skipping Aligners Tools Setting
if( params.skip_aligners ){
    skip_aligners = params.skip_aligners
    skip_bwa = true
    skip_tophat2 = true
    skip_hisat2 = true
    skip_star = true
}else{
    skip_aligners = params.skip_aligners
    skip_bwa = params.skip_bwa
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_star = params.skip_star
}

/*
 * Create a channel for input read files
 */
if( params.readPaths && !params.skip_aligners ){
    if( params.singleEnd ){
        Channel
            .fromFilePairs( "${params.readPaths}/*.fastq", size: 1 ) 
            //.map { row -> [ row[0], [file(row[1][0])]] }
            .ifEmpty { exit 1, LikelikeUtils.print_red( "readPaths was empty - no input files supplied: ${params.readPaths}" )}
            //.subscribe { println it }
            .into{ raw_data; raw_bam }
    }
    else if ( !params.singleEnd ){
        Channel
            .fromFilePairs( "${params.readPaths}/*{1,2}.fastq", size: 2 ) 
            //.map { row -> [ row[0], [file(row[1][0])]] }
            .ifEmpty { exit 1, LikelikeUtils.print_red( "readPaths was empty - no input files supplied: ${params.readPaths}" )}
            //.subscribe { println it }
            .into{ raw_data; raw_bam }
    }
    else {
        exit 1, LikelikeUtils.print_red("The param 'singleEnd' was not defined!")
    }
}else if( params.readPaths && params.skip_aligners ){
    Channel
        .fromPath( "$params.readPaths/*.bam") 
        //.map { row -> [ row[0], [file(row[1][0])]] }
        .ifEmpty { exit 1, LikelikeUtils.print_red( "readPaths was empty - no input files supplied: ${params.readPaths}" )}
        //.subscribe { println it }
        .into{ raw_data; raw_bam }
} 
else{
    LikelikeUtils.print_red( "readPaths was empty: ${params.readPaths}")
}
/*
========================================================================================
                             check or build the index
========================================================================================
*/ 
/*
 * PREPROCESSING - Build BED12 file
 * NEED gtf.file
 */
if(params.gtf && !params.bed12){
    process makeBED12 {
        tag "gtf2bed12"
        publishDir path: { params.saveReference ? "${params.outdir}/Genome/reference_genome" : params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'

        input:
        file gtf
        
        output:
        file "${gtf.baseName}.bed" into bed_rseqc, bed_genebody_coverage

        script:      
        """
        bash ${baseDir}/bin/gtf2bed12.sh $gtf
        """        
    }
}

/*
 * PREPROCESSING - Build TOPHAT2 index
 * NEED genome.fa
 */
if( params.tophat2_index && !params.skip_aligners){
    tophat2_index = Channel
        .fromPath(params.tophat2_index)
        .ifEmpty { exit 1, "Tophat2 index not found: ${params.tophat2_index}" }
}else if( params.fasta ){
    process MakeTophat2Index {
        tag "tophat2_index"
        publishDir path: { params.saveReference ? "${params.outdir}/Genome/": params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'
        input:
        file fasta

        output:
        file "Tophat2Index/*" into tophat2_index

        when:
        !params.skip_tophat2 && !params.skip_aligners

        script:
        tophat2_index = "Tophat2Index/" + fasta.baseName.toString()
        """
        mkdir Tophat2Index
        bowtie2-build -f $params.fasta $tophat2_index
        """
    }
}else {
    exit 1, LikelikeUtils.print_red("There is no Tophat2 Index")
}

/*
 * PREPROCESSING - Build HISAT2 index
 * NEED genome.fa genes.gtf snp.txt/vcf
 */
if( params.hisat2_index && !params.skip_aligners ){
    hisat2_index = Channel
        .fromPath(params.hisat2_index)
        .ifEmpty { exit 1, "hisat2 index not found: ${params.hisat2_index}" }
}else if( params.fasta){
    process MakeHisat2Index {
        tag "hisat2_index"
        publishDir path: { params.saveReference ? "${params.outdir}/Genome/ " : params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'        
        input:
        file fasta
        file gtf
        //file params.snp

        output:
        file "Hisat2Index/*" into hisat2_index

        when:
        !params.skip_hisat2 && !params.skip_aligners
        
        script:
        """
        mkdir Hisat2Index
        hisat2_extract_exons.py $gtf > Hisat2Index/${gtf.baseName}.exon
        hisat2_extract_splice_sites.py $gtf > Hisat2Index/${gtf.baseName}.ss
        #hisat2_extract_splice_sites.py ${params.snp} > Hisat2Index/${gtf.baseName}.snp
        hisat2-build -p ${task.cpus} -f $fasta --snp Hisat2Index/${gtf.baseName}.snp --exon Hisat2Index/${gtf.baseName}.exon --ss Hisat2Index/${gtf.baseName}.ss Hisat2Index/${fasta.baseName}
        """
    }
}else {
    exit 1, LikelikeUtils.print_red("There is no Hisat2 Index")
}

/*
 * PREPROCESSING - Build BWA index
 * NEED genome.fa
 */
if( params.bwa_index && !params.skip_aligners){
    bwa_index = Channel
        .fromPath( params.bwa_index )
        .ifEmpty { exit 1, "bwa index not found: ${params.bwa_index}" }
}else if(params.fasta ){
    process MakeBWAIndex {
        tag "bwa_index"
        publishDir path: { params.saveReference ? "${params.outdir}/Genome/" : params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'

        input:
        file fasta

        output:
        file "BWAIndex/*" into bwa_index

        when:
        !params.skip_bwa && !params.skip_aligners
     
        script:
        """
        mkdir BWAIndex
        cd BWAIndex/
        bwa index -b ${task.cpus} -p ${fasta.baseName} -abwtsw ../$fasta
        cd ../
        """
    }
}else {
    exit 1, LikelikeUtils.print_red("There is no BWA Index")
}

/*
 * PREPROCESSING - Build STAR index
 * NEED genome.fa genes.gtf
 */
if( params.star_index && !params.skip_aligners){
    star_index = Channel
        .fromPath(params.star_index)
        .ifEmpty { exit 1, "STAR index not found: ${params.star_index}" }
}else if( params.fasta ){
    process MakeStarIndex {
        tag "star_index"
        publishDir path: { params.saveReference ? "${params.outdir}/Genome/" : params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'
        input:
        file fasta
        file gtf

        output:
        file "StarIndex" into star_index

        when:
        !params.skip_star && !params.skip_aligners 

        script:
        readLength = 50
        overhang = readLength - 1
        """
        mkdir StarIndex
        STAR --runThreadN ${task.cpus} \
        --runMode genomeGenerate \
        --genomeDir StarIndex \
        --genomeFastaFiles $fasta \
        --sjdbGTFfile $gtf \
        --sjdbOverhang $overhang 
        """
    }
}else {
   exit 1, LikelikeUtils.print_red("There is no STAR Index")
}
/*
========================================================================================
                                Step 1. QC------FastQC
========================================================================================
*/ 
process Fastqc{
    tag "$sample_name"
    publishDir "${params.outdir}/fastqc", mode: 'link', overwrite: true

    input:
    set sample_name, file(reads) from raw_data

    output:
    val sample_name into pair_id_tophat2, pair_id_hisat2, pair_id_bwa, pair_id_star 
    file "*.fastq" into tophat2_reads, hisat2_reads, bwa_reads, star_reads
    file "*" into fastqc_results

    when:
    !params.skip_aligners

    shell:
    skip_fastqc = params.skip_fastqc
    if (params.singleEnd) {
        filename = reads.toString() - ~/(_trimmed)?(_val_1)?(_Clean)?(_[0-9])?(\.fq)?(\.fastq)?(\.gz)?$/
        sample_name = filename
        add_aligners = reads.toString() - ~/(\.fq)?(\.fastq)?$/ + "_aligners.fastq"
        """
        if [ $skip_fastqc == "false" ]; then
            mkdir fastqc
            fastqc -o fastqc --noextract ${reads}
            fi
        mv ${reads} ${add_aligners}
        """       
    } else {
        filename = reads[0].toString() - ~/(_trimmed)?(_val_1)?(_Clean)?(_[0-9])?(\.fq)?(\.fastq)?(\.gz)?$/
        sample_name = filename
        add_aligners_1 = reads[0].toString() - ~/(\.fq)?(\.fastq)?$/ + "_aligners.fastq"
        add_aligners_2 = reads[1].toString() - ~/(\.fq)?(\.fastq)?$/ + "_aligners.fastq"
        """
        if [ $skip_fastqc == "false" ]; then
            mkdir fastqc   
            fastqc -o fastqc --noextract ${reads[0]}
            fastqc -o fastqc --noextract ${reads[1]}
            fi
        mv ${reads[0]} ${add_aligners_1}
        mv ${reads[1]} ${add_aligners_2}
        """      
    }
}
/*
========================================================================================
                            Step 2. Reads Mapping
========================================================================================
*/ 
process Tophat2Align {
    tag "$sample_name"
    publishDir "${params.outdir}/aligners/tophat2", mode: 'link', overwrite: true

    input:
    val sample_name from pair_id_tophat2
    file(reads) from tophat2_reads
    file index from tophat2_index.collect()
    file gtf

    output:
    file "*_tophat2.bam" into tophat2_bam
    
    when:
    !params.skip_tophat2 && !params.skip_aligners

    script:
    index_base = index[0].toString() - ~/(\.rev)?(\.\d)?(\.fa)?(\.bt2)?$/
    strand_str = unstranded ? "fr-unstranded" : "fr-firststrand"
    if (params.singleEnd) {
        """
        tophat  -p ${task.cpus} \
                -G $gtf \
                -o $sample_name \
                --no-novel-juncs \
                --library-type $strand_str \
                $index_base \
                $reads &> ${sample_name}_log.txt
        mv $sample_name/accepted_hits.bam ${reads.baseName}_tophat2.bam
        """
    } else {
        """
        tophat -p ${task.cpus} \
                -G $gtf \
                -o $sample_name \
                --no-novel-juncs \
                --library-type $strand_str \
                $index_base \
                ${reads[0]} ${reads[1]} &> ${sample_name}_log.txt
        mv $sample_name/accepted_hits.bam ${sample_name}_tophat2.bam
        """
    }
}

process Hisat2Align {
    tag "$sample_name"
    publishDir "${params.outdir}/aligners/hisat2", mode: 'link', overwrite: true

    input:
    val sample_name from pair_id_hisat2
    file(reads) from hisat2_reads
    file index from hisat2_index.collect()

    output:
    file "*_hisat2.bam" into hisat2_bam

    when:
    !params.skip_hisat2 && !params.skip_aligners

    script:
    index_base = index[0].toString() - ~/(\.exon)?(\.\d)?(\.fa)?(\.gtf)?(\.ht2)?$/
    if (params.singleEnd) {
        """
        hisat2  -p ${task.cpus} --dta \
                -x $index_base \
                -U $reads \
                -S ${reads.baseName}_hisat2.sam 2> ${reads.baseName}_hisat2_summary.txt
        samtools view -@ ${task.cpus} -h -bS ${reads.baseName}_hisat2.sam > ${reads.baseName}_hisat2.bam
        rm *.sam
        """
    } else {
        """
        hisat2  -p ${task.cpus} --dta \
                -x $index_base \
                -1 ${reads[0]} -2 ${reads[1]} \
                -S ${sample_name}_hisat2.sam 2> ${sample_name}_hisat2_summary.txt
        samtools view -@ ${task.cpus} -h -bS ${sample_name}_hisat2.sam > ${sample_name}_hisat2.bam
        rm *.sam
        """
        }
}

process BWAAlign{
    tag "$sample_name"
    publishDir "${params.outdir}/aligners/bwa", mode: 'link', overwrite: true
    
    input:
    val sample_name from pair_id_bwa
    file(reads) from bwa_reads
    file index from bwa_index.collect()

    output:
    file "*_bwa.bam" into bwa_bam

    when:
    !params.skip_bwa && !params.skip_aligners

    script:
    index_base = index[0].toString() - ~/(\.pac)?(\.bwt)?(\.ann)?(\.amb)?(\.sa)?(\.fa)?$/
    if (params.singleEnd) {
        """
        bwa aln -t ${task.cpus} \
                -f ${reads.baseName}.sai \
                $index_base \
                $reads
        bwa samse -f ${reads.baseName}_bwa.sam \
                $index_base \
                ${reads.baseName}.sai \
                $reads &> ${sample_name}_log.txt
        samtools view -@ ${task.cpus} -h -bS ${reads.baseName}_bwa.sam > ${reads.baseName}_bwa.bam
        rm *.sam
        """
    } else {
        """
        bwa aln -t ${task.cpus} \
                -f ${reads[1].baseName}.sai \
                $index_base \
                ${reads[0]}
        bwa aln -t ${task.cpus} \
                -f ${reads[1].baseName}.sai \
                $index_base \
                ${reads[1]}
        bwa sampe -f ${sample_name}_bwa.sam \
                $index_base \
                ${reads[1].baseName}.sai ${reads[1].baseName}.sai \
                ${reads[0]} ${reads[1]} &> ${sample_name}_log.txt
        samtools view -@ ${task.cpus} -h -bS ${sample_name}_bwa.sam > ${sample_name}_bwa.bam
        rm *.sam
        """
    }
}

process StarAlign {
    tag "$sample_name"
    publishDir "${params.outdir}/aligners/star", mode: 'link', overwrite: true
    
    input:
    val sample_name from pair_id_star
    file(reads) from star_reads
    file star_index from star_index.collect()

    output:
    file "*_star.bam" into star_bam

    when:
    !params.skip_star && !params.skip_aligners

    script:
    if (params.singleEnd) {
        """
        STAR --runThreadN ${task.cpus} \
            --twopassMode Basic \
            --genomeDir $star_index \
            --readFilesIn $reads  \
            --outSAMtype BAM Unsorted \
            --alignSJoverhangMin 8 --alignSJDBoverhangMin 1 \
            --outFilterIntronMotifs RemoveNoncanonical \
            --outFilterMultimapNmax 20 \
            --alignIntronMin 20 \
            --alignIntronMax 1000000 \
            --alignMatesGapMax 1000000 \
            --outFileNamePrefix ${reads.baseName}  &> ${sample_name}_log.txt
        mv ${reads.baseName}Aligned.out.bam ${reads.baseName}_star.bam
        """
    } else {
        """
        STAR --runThreadN ${task.cpus} \
            --twopassMode Basic \
            --genomeDir $star_index \
            --readFilesIn ${reads[0]} ${reads[1]}  \
            --outSAMtype BAM Unsorted \
            --alignSJoverhangMin 8 --alignSJDBoverhangMin 1 \
            --outFilterIntronMotifs RemoveNoncanonical \
            --outFilterMultimapNmax 20 \
            --alignIntronMin 20 \
            --alignIntronMax 1000000 \
            --alignMatesGapMax 1000000 \
            --outFileNamePrefix ${sample_name} &> ${sample_name}_log.txt
        mv ${sample_name}Aligned.out.bam ${sample_name}_star.bam
        """
    }
}
/*
========================================================================================
                        Step 3 Sort BAM file AND QC
========================================================================================
*/ 
Channel
    .from()
    .concat(tophat2_bam, hisat2_bam, bwa_bam, star_bam, raw_bam)
    .into {merge_bam_file; test_channel1}
//test_channel1.subscribe{ println it }
/*
 * STEP 3-1 - Sort BAM file
*/
process RenameByDesignfile{
    //publishDir "${params.outdir}/Sample_rename", mode: 'link', overwrite: true

    input:
    file (reads) from merge_bam_file.collect()
    file designfile  // designfile:filename,control_treated,input_ip

    output:
    file ("*.bam") into rename_bam_file
    file ("formatted_designfile.txt") into formatted_designfile
    
    when:
    true

    script:
    if ( params.singleEnd == true ) {
        """
        #Windows and linux newline ^M conversion
        cat $designfile > formatted_designfile.txt 
        dos2unix formatted_designfile.txt  
        if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/rename.sh tophat2 formatted_designfile.txt; fi
        if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/rename.sh hisat2 formatted_designfile.txt; fi
        if [ $skip_bwa == "false" ]; then bash $baseDir/bin/rename.sh bwa formatted_designfile.txt; fi
        if [ $skip_star == "false" ]; then bash $baseDir/bin/rename.sh star formatted_designfile.txt; fi
        if [ $skip_aligners == "true" ]; then bash $baseDir/bin/rename.sh aligners formatted_designfile.txt; fi     
        """
    } else {
        """
        #Windows and linux newline ^M conversion
        cat $designfile > formatted_designfile.txt 
        dos2unix formatted_designfile.txt  
        if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/rename.sh tophat2 formatted_designfile.txt; fi
        if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/rename.sh hisat2 formatted_designfile.txt; fi
        if [ $skip_bwa == "false" ]; then bash $baseDir/bin/rename.sh bwa formatted_designfile.txt; fi
        if [ $skip_star == "false" ]; then bash $baseDir/bin/rename.sh star formatted_designfile.txt; fi
        if [ $skip_aligners == "true" ]; then bash $baseDir/bin/rename.sh aligners formatted_designfile.txt; fi     
        """
    }
}
process Sort {
    publishDir "${params.outdir}/samtools_sort/", mode: 'link', overwrite: true

    input:
    file( bam_query_file ) from rename_bam_file.collect()

    output:
    file "*_sort*" into macs2_bam, metpeak_bam, metdiff_bam, 
                        htseq_count_bam, rseqc_bam, genebody_bam,
                        cufflinks_bam, matk_bam, diffmatk_bam, 
                        bam_for_counting_peaks

    script:
    if (!params.skip_sort){
        """    
        if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/samtools_sort.sh tophat2 ${task.cpus}; fi
        if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/samtools_sort.sh hisat2 ${task.cpus}; fi
        if [ $skip_bwa == "false" ]; then bash $baseDir/bin/samtools_sort.sh bwa ${task.cpus}; fi
        if [ $skip_star == "false" ]; then bash $baseDir/bin/samtools_sort.sh star ${task.cpus}; fi
        if [ $skip_aligners == "true" ]; then bash $baseDir/bin/samtools_sort.sh aligners ${task.cpus}; fi
        """
    } else {
        '''
        for bam_file in *.bam
        do
        {
            mv ${bam_file} ${bam_file/.bam/_sort.bam}
        }
        done
        '''
    }
   
}
/*
 * STEP 3-2 - RSeQC analysis
*/
process RSeQC {
    publishDir "${params.outdir}/rseqc" , mode: 'copy', overwrite: true,
        saveAs: {filename ->
                 if (filename.indexOf("bam_stat.txt") > 0)                      "bam_stat/$filename"
            else if (filename.indexOf("infer_experiment.txt") > 0)              "infer_experiment/$filename"
            else if (filename.indexOf("read_distribution.txt") > 0)             "read_distribution/$filename"
            else if (filename.indexOf("read_duplication.DupRate_plot.pdf") > 0) "read_duplication/$filename"
            else if (filename.indexOf("read_duplication.DupRate_plot.r") > 0)   "read_duplication/rscripts/$filename"
            else if (filename.indexOf("read_duplication.pos.DupRate.xls") > 0)  "read_duplication/dup_pos/$filename"
            else if (filename.indexOf("read_duplication.seq.DupRate.xls") > 0)  "read_duplication/dup_seq/$filename"
            else if (filename.indexOf("RPKM_saturation.eRPKM.xls") > 0)         "RPKM_saturation/rpkm/$filename"
            else if (filename.indexOf("RPKM_saturation.rawCount.xls") > 0)      "RPKM_saturation/counts/$filename"
            else if (filename.indexOf("RPKM_saturation.saturation.pdf") > 0)    "RPKM_saturation/$filename"
            else if (filename.indexOf("RPKM_saturation.saturation.r") > 0)      "RPKM_saturation/rscripts/$filename"
            else if (filename.indexOf("inner_distance.txt") > 0)                "inner_distance/$filename"
            else if (filename.indexOf("inner_distance_freq.txt") > 0)           "inner_distance/data/$filename"
            else if (filename.indexOf("inner_distance_plot.r") > 0)             "inner_distance/rscripts/$filename"
            else if (filename.indexOf("inner_distance_plot.pdf") > 0)           "inner_distance/plots/$filename"
            else if (filename.indexOf("junction_plot.r") > 0)                   "junction_annotation/rscripts/$filename"
            else if (filename.indexOf("junction.xls") > 0)                      "junction_annotation/data/$filename"
            else if (filename.indexOf("splice_events.pdf") > 0)                 "junction_annotation/events/$filename"
            else if (filename.indexOf("splice_junction.pdf") > 0)               "junction_annotation/junctions/$filename"
            else if (filename.indexOf("junctionSaturation_plot.pdf") > 0)       "junction_saturation/$filename"
            else if (filename.indexOf("junctionSaturation_plot.r") > 0)         "junction_saturation/rscripts/$filename"
            else filename
        }    
    when:
    !params.skip_qc && !params.skip_rseqc

    input:
    file bam_rseqc from rseqc_bam
    file bed12 from bed_rseqc.collect()

    output:
    file "*.{txt,pdf,r,xls}" into rseqc_results
    file "*.bam_stat.txt" into bam_stat_for_normlization
    script:
    /* 
    def strandRule = ''
    if (forward_stranded && !unstranded){
        strandRule = params.singleEnd ? '-d ++,--' : '-d 1++,1--,2+-,2-+'
    } else if (reverse_stranded && !unstranded){
        strandRule = params.singleEnd ? '-d +-,-+' : '-d 1+-,1-+,2++,2--'
    }
    */
    """    
    if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/rseqc.sh tophat2 $bed12 ; fi &
    if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/rseqc.sh hisat2 $bed12; fi &
    if [ $skip_bwa == "false" ]; then bash $baseDir/bin/rseqc.sh bwa $bed12 ; fi &
    if [ $skip_star == "false" ]; then bash $baseDir/bin/rseqc.sh star $bed12 ; fi &
    if [ $skip_aligners == "true" ]; then bash $baseDir/bin/rseqc.sh aligners $bed12 ; fi &
    """
}

process CreateBigWig {
    publishDir "${params.outdir}/rseqc/bigwig", mode: 'link', overwrite: true 

    input:
    file bam from genebody_bam

    output:
    file "*.bigwig" into bigwig_for_genebody

    when:
    !params.skip_rseqc && !params.skip_genebody_coverage 

    script:
    """
    bash $baseDir/bin/create_bigwig.sh ${task.cpus}
    """
}

process GenebodyCoverage {
       publishDir "${params.outdir}/rseqc" , mode: 'link', overwrite: true, 
        saveAs: {filename ->
            if (filename.indexOf("geneBodyCoverage.curves.pdf") > 0)       "geneBodyCoverage/$filename"
            else if (filename.indexOf("geneBodyCoverage.r") > 0)           "geneBodyCoverage/rscripts/$filename"
            else if (filename.indexOf("geneBodyCoverage.txt") > 0)         "geneBodyCoverage/data/$filename"
            else if (filename.indexOf("log.txt") > -1) false
            else filename
        }

    when:
    !params.skip_rseqc && !params.skip_genebody_coverage

    input:
    file bigwig from bigwig_for_genebody
    file bed12 from bed_genebody_coverage.collect()

    output:
    file "*.{txt,pdf,r}" into genebody_coverage_results

    script:
    """
    bash $baseDir/bin/geneBody_coverage2.sh $bed12 ${task.cpus}
    """
}
/*
========================================================================================
                            Step 4 Peak Calling
========================================================================================
*/ 
/*
 * STEP 4 - 1  Peak Calling------MetPeak, MACS2, MATK
*/
process Metpeak {
    publishDir "${params.outdir}/peak_calling/metpeak", mode: 'link', overwrite: true

    input:
    file bam_bai_file from metpeak_bam
    file gtf
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "*" into metpeak_results
    file "metpeak*.bed" into metpeak_bed, metpeak_for_annotate

    when:
    !params.skip_metpeak && !params.skip_peakCalling

    script: 
    """
    if [ $skip_tophat2 == "false" ]; then
        Rscript $baseDir/bin/MeTPeak.R tophat2 $formatted_designfile $gtf;
        fi
    if [ $skip_hisat2 == "false" ]; then
        Rscript $baseDir/bin/MeTPeak.R hisat2 $formatted_designfile $gtf;
        fi
    if [ $skip_bwa == "false" ]; then
        Rscript $baseDir/bin/MeTPeak.R bwa $formatted_designfile $gtf;
        fi
    if [ $skip_star == "false" ]; then
        Rscript $baseDir/bin/MeTPeak.R star $formatted_designfile $gtf;
        fi
    if [ $skip_aligners == "true" ]; then
        Rscript $baseDir/bin/MeTPeak.R aligners $formatted_designfile $gtf ;
        fi
    """
}

process Macs2{
    publishDir "${params.outdir}/peak_calling/macs2", mode: 'link', overwrite: true

    input:
    file bam_bai_file from macs2_bam
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "macs2*.xls" into macs2_results
    file "macs2*.summits" into macs2_summits
    file "macs2*.bed" into macs2_for_annotate
    file "macs2*.narrowPeak" into macs2_narrowPeak

    when:
    !params.skip_macs2 && !params.skip_peakCalling

    script:
    """
    if [ $skip_tophat2 == "false" ]; then
        bash $baseDir/bin/macs2.sh tophat2 $formatted_designfile ${task.cpus};
        fi 
    if [ $skip_hisat2 == "false" ]; then 
        bash $baseDir/bin/macs2.sh hisat2 $formatted_designfile ${task.cpus};
        fi 
    if [ $skip_bwa == "false" ]; then
        bash $baseDir/bin/macs2.sh bwa $formatted_designfile ${task.cpus};
        fi 
    if [ $skip_star == "false" ]; then
        bash $baseDir/bin/macs2.sh star $formatted_designfile ${task.cpus};
        fi 
    if [ $skip_aligners == "true" ]; then
        bash $baseDir/bin/macs2.sh aligners $formatted_designfile ${task.cpus};
        fi
    """ 
}
process MATKpeakCalling {
    publishDir "${params.outdir}/peak_calling/MATK", mode: 'link', overwrite: true

    input:
    file bam_bai_file from matk_bam
    file gtf
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "*" into matk_results
    file "MATK*.bed" into matk_bed, matk_bed_for_diffmatk, matk_for_annotate
    
    when:
    !params.skip_matk && !params.skip_peakCalling

    script:
    matk_jar = baseDir + "/bin/MATK-1.0.jar"

    """
    if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/MATK_peakCalling.sh tophat2 $matk_jar $formatted_designfile ${task.cpus};fi 
    if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/MATK_peakCalling.sh hisat2 $matk_jar $formatted_designfile ${task.cpus}; fi 
    if [ $skip_bwa == "false" ]; then bash $baseDir/bin/MATK_peakCalling.sh bwa $matk_jar $formatted_designfile ${task.cpus}; fi 
    if [ $skip_star == "false" ]; then bash $baseDir/bin/MATK_peakCalling.sh star $matk_jar $formatted_designfile ${task.cpus}; fi     
    if [ $skip_aligners == "true" ]; then bash $baseDir/bin/MATK_peakCalling.sh aligners $matk_jar $formatted_designfile ${task.cpus}; fi
    """    
}
/*
 * STEP 4 - 2 Differential methylation analysis------MetDiff, QNB, MATK
*/

process Metdiff {
    publishDir "${params.outdir}/diff_peak_calling/metdiff", mode: 'link', overwrite: true

    input:
    file bam_bai_file from metdiff_bam
    file gtf
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "*" into metdiff_results
    file "metdiff*.bed" into metdiff_bed, metdiff_for_annotate

    when:
    !params.skip_metdiff && !params.skip_diffpeakCalling

    script:
    treated_situation_startpoint = TREATED_SITUATION_STARTPOINT
    """
    if [ $skip_tophat2 == "false" ]; then
        Rscript $baseDir/bin/MeTDiff.R $treated_situation_startpoint tophat2 $formatted_designfile $gtf;
        fi
    if [ $skip_hisat2 == "false" ]; then
        Rscript $baseDir/bin/MeTDiff.R $treated_situation_startpoint hisat2 $formatted_designfile $gtf;
        fi
    if [ $skip_bwa == "false" ]; then
        Rscript $baseDir/bin/MeTDiff.R $treated_situation_startpoint bwa $formatted_designfile $gtf;
        fi
    if [ $skip_star == "false" ]; then
        Rscript $baseDir/bin/MeTDiff.R $treated_situation_startpoint star $formatted_designfile $gtf;
        fi
    if [ $skip_aligners == "true" ]; then    
        Rscript $baseDir/bin/MeTDiff.R $treated_situation_startpoint aligners $formatted_designfile $gtf ;
        fi
    """ 
}
process MATKdiffpeakCalling {
    publishDir "${params.outdir}/diff_peak_calling/MATK", mode: 'link', overwrite: true

    input:
    file bam_bai_file from diffmatk_bam
    file gtf
    file bed from matk_bed_for_diffmatk.collect()
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "*" into diffmatk_results
    file "diffMATK*.bed" into diffmatk_bed, diffmatk_for_annotate
    
    when:
    !params.skip_diffmatk && !params.skip_diffpeakCalling

    script:
    matk_jar = baseDir + "/bin/MATK-1.0.jar"
    treated_situation_startpoint = TREATED_SITUATION_STARTPOINT
    """
    if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/MATK_diffpeakCalling.sh $treated_situation_startpoint tophat2 $matk_jar $formatted_designfile $gtf ${task.cpus};fi 
    if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/MATK_diffpeakCalling.sh $treated_situation_startpoint hisat2 $matk_jar $formatted_designfile $gtf ${task.cpus}; fi 
    if [ $skip_bwa == "false" ]; then bash $baseDir/bin/MATK_diffpeakCalling.sh $treated_situation_startpoint bwa $matk_jar $formatted_designfile $gtf ${task.cpus}; fi 
    if [ $skip_star == "false" ]; then bash $baseDir/bin/MATK_diffpeakCalling.sh $treated_situation_startpoint star $matk_jar $formatted_designfile $gtf ${task.cpus}; fi   
    if [ $skip_aligners == "true" ]; then bash $baseDir/bin/MATK_diffpeakCalling.sh $treated_situation_startpoint  aligners $matk_jar $formatted_designfile $gtf ${task.cpus}; fi
    """     
}

process Htseq_count{
    publishDir "${params.outdir}/diff_expression/htseq_count", mode: 'link', overwrite: true

    input:
    file bam_bai_file from htseq_count_bam
    file formatted_designfile from formatted_designfile.collect()
    file gtf

    output:
    file "*input*.count" into htseq_count_input_to_QNB, htseq_count_input_to_deseq2, htseq_count_input_to_edgeR, htseq_count_input_to_arrange
    file "*ip*.count" into htseq_count_ip_to_QNB, htseq_count_ip_to_arrange

    when:
    !params.skip_QNB && !params.skip_diffpeakCalling

    script:
    """
    if [ $skip_tophat2 == "false" ]; then
        bash $baseDir/bin/htseq_count.sh tophat2 $gtf ${task.cpus} ; 
        Rscript $baseDir/bin/get_htseq_matrix.R tophat2 $formatted_designfile ;
        fi
    if [ $skip_hisat2 == "false" ]; then
        bash $baseDir/bin/htseq_count.sh hisat2 $gtf ${task.cpus} ; 
        Rscript $baseDir/bin/get_htseq_matrix.R hisat2 $formatted_designfile ;
        fi
    if [ $skip_bwa == "false" ]; then
        bash $baseDir/bin/htseq_count.sh bwa $gtf ${task.cpus} ; 
        Rscript $baseDir/bin/get_htseq_matrix.R bwa $formatted_designfile ;
        fi
    if [ $skip_star == "false" ]; then
        bash $baseDir/bin/htseq_count.sh star $gtf ${task.cpus} ; 
        Rscript $baseDir/bin/get_htseq_matrix.R star $formatted_designfile ;
        fi
    if [ $skip_aligners == "true" ]; then   
        bash $baseDir/bin/htseq_count.sh aligners $gtf ${task.cpus}  
        Rscript $baseDir/bin/get_htseq_matrix.R aligners $formatted_designfile ;
        fi
        """ 
}

process QNB {
    publishDir "${params.outdir}/diff_peak_calling/QNB", mode: 'link', overwrite: true

    input:
    file reads_count_input from htseq_count_input_to_QNB
    file reads_count_ip from htseq_count_ip_to_QNB
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "*" into qnb_results
    
    when:
    !params.skip_QNB && !params.skip_diffpeakCalling

    script:  
    treated_situation_startpoint = TREATED_SITUATION_STARTPOINT    
    """
    if [ $skip_tophat2 == "false" ]; then
        Rscript $baseDir/bin/QNB.R $treated_situation_startpoint tophat2 $formatted_designfile ;
        fi
    if [ $skip_hisat2 == "false" ]; then
        Rscript $baseDir/bin/QNB.R $treated_situation_startpoint hisat2 $formatted_designfile ;
        fi
    if [ $skip_bwa == "false" ]; then
        Rscript $baseDir/bin/QNB.R $treated_situation_startpoint bwa $formatted_designfile ;
        fi
    if [ $skip_star == "false" ]; then
        Rscript $baseDir/bin/QNB.R $treated_situation_startpoint star $formatted_designfile ;
        fi
    if [ $skip_aligners == "true" ]; then
        Rscript $baseDir/bin/QNB.R $treated_situation_startpoint aligners $formatted_designfile ;
        fi
    """ 
}
/*
========================================================================================
                        Step 5 Differential expression analysis
========================================================================================
*/
process Deseq2{
    publishDir "${params.outdir}/diff_expression/deseq2", mode: 'link', overwrite: true

    input:
    file reads_count_input from htseq_count_input_to_deseq2
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "Deseq2*.csv" into deseq2_results
    
    when:
    !params.skip_deseq2 && !params.skip_expression

    script:
    treated_situation_startpoint = TREATED_SITUATION_STARTPOINT
    """
    if [ $skip_tophat2 == "false" ]; then
        Rscript $baseDir/bin/DESeq2.R $treated_situation_startpoint tophat2 $formatted_designfile ;
        fi
    if [ $skip_hisat2 == "false" ]; then
        Rscript $baseDir/bin/DESeq2.R $treated_situation_startpoint hisat2 $formatted_designfile ;
        fi
    if [ $skip_bwa == "false" ]; then
        Rscript $baseDir/bin/DESeq2.R $treated_situation_startpoint bwa $formatted_designfile ;
        fi
    if [ $skip_star == "false" ]; then
        Rscript $baseDir/bin/DESeq2.R $treated_situation_startpoint star $formatted_designfile ;
        fi
    if [ $skip_aligners == "true" ]; then  
        Rscript $baseDir/bin/DESeq2.R $treated_situation_startpoint aligners $formatted_designfile ;
        fi
    """ 

}

process EdgeR{
    publishDir "${params.outdir}/diff_expression/edgeR", mode: 'link', overwrite: true

    input:
    file reads_count_input from htseq_count_input_to_edgeR
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "edgeR*.csv" into edgeR_results
    
    when:
    !params.skip_edger && !params.skip_expression

    script:
    treated_situation_startpoint = TREATED_SITUATION_STARTPOINT
    """
    if [ $skip_tophat2 == "false" ]; then
        Rscript $baseDir/bin/edgeR.R $treated_situation_startpoint tophat2 $formatted_designfile ;
        fi
    if [ $skip_hisat2 == "false" ]; then
        Rscript $baseDir/bin/edgeR.R $treated_situation_startpoint hisat2 $formatted_designfile ;
        fi
    if [ $skip_bwa == "false" ]; then
        Rscript $baseDir/bin/edgeR.R $treated_situation_startpoint bwa $formatted_designfile ;
        fi
    if [ $skip_star == "false" ]; then
        Rscript $baseDir/bin/edgeR.R $treated_situation_startpoint star $formatted_designfile ;
        fi
    if [ $skip_aligners == "true" ]; then     
        Rscript $baseDir/bin/edgeR.R $treated_situation_startpoint aligners $formatted_designfile ;
        fi
    """ 
}

process Cufflinks{
    publishDir "${params.outdir}/diff_expression/cufflinks", mode: 'link', overwrite: true

    input:
    file bam_bai_file from cufflinks_bam
    file gtf
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "cuffdiff_*" into cufflinks_results

    when:
    !params.skip_cufflinks && !params.skip_expression

    script:
    """
    if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/cufflinks.sh tophat2 $formatted_designfile $gtf ${task.cpus}; fi
    if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/cufflinks.sh hisat2 $formatted_designfile $gtf ${task.cpus}; fi
    if [ $skip_bwa == "false" ]; then bash $baseDir/bin/cufflinks.sh bwa $formatted_designfile $gtf ${task.cpus}; fi
    if [ $skip_star == "false" ]; then bash $baseDir/bin/cufflinks.sh star $formatted_designfile $gtf ${task.cpus}; fi   
    if [ $skip_aligners == "true" ]; then bash $baseDir/bin/cufflinks.sh aligners $formatted_designfile $gtf ${task.cpus}; fi
    """ 
}

/*
========================================================================================
                        Step 6 Merge Peak AND Analysis
========================================================================================
*/
/*
 * STEP 5-1 Merge Peak
*/
Channel
    .from()
    .concat(metpeak_bed, macs2_narrowPeak, matk_bed)
    .into {mspc_merge_peak_bed; bedtools_merge_peak_bed; bed_for_motif_searching; }

Channel
    .from()
    .concat(metdiff_bed, diffmatk_bed)
    .into {mspc_merge_diffpeak_bed; bedtools_merge_diffpeak_bed; diffbed_for_motif_searching }

process PeakMergeBYMspc {
    publishDir "${params.outdir}/peak_calling/merge_peak/mspc", mode: 'link', overwrite: true
    
    input:
    file peak_bed from mspc_merge_peak_bed.collect()
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "mspc_situation*.bed" into mspc_merge_bed_for_annotate

    when:
    !params.skip_mspc && !params.skip_peakCalling

    shell:
    mspc_directory = baseDir + "/bin/mspc_v3.3"
    '''
    for bed_file in *.bed
    do
        #Scientific notation converted to numbers
        cat $bed_file | awk 'BEGIN{FS="\t";OFS="\t"}NR>1{print $1,$2*1,$3*1,$1":"$2"-"$3,-log($5)/log(10)}' | sortBed -i - >  ${bed_file/.bed/_sort.bed} 
    done
    for macs2_file in macs2*.narrowPeak
    do
        #Scientific notation converted to numbers
        cat $macs2_file | awk 'BEGIN{FS="\t";OFS="\t"}NR>1{print $1,$2*1,$3*1,$1":"$2"-"$3,$8}' | sortBed -i - >  ${macs2_file/_peaks.narrowPeak/_sort.bed} 
    done

    ln -s !{mspc_directory}/* ./
    MAX_SITUATION=$(awk -F, '{if(NR>1)print int($3)}' !{formatted_designfile} | sort -r | head -1)
    for ((i=1;i<=$MAX_SITUATION;i++))
    do
        count=$(ls *situation_${i}*sort.bed | wc -w)
        if [ $count -gt 1 ]; then
            ls *situation_${i}*sort.bed | awk '{ORS=" "}{print "-i",$0}'| awk '{print "dotnet CLI.dll",$0,"-r Tec -w 1E-4 -s 1E-8 > situation_'${i}'.log "}' | bash
            mv */ConsensusPeaks.bed mspc_situation_${i}.bed
        else 
            ln *situation_${i}*sort.bed mspc_situation_${i}.bed
        fi
    done
    ls mspc*.bed | awk '{ORS=" "}{print "-i",$0}'| awk '{print "dotnet CLI.dll",$0,"-r Tec -w 1E-4 -s 1E-8 > situation_merged.log"}' | bash
    mv */ConsensusPeaks.bed mspc_merged_peaks.bed
    '''
}

process DiffPeakMergeBYMspc {
    publishDir "${params.outdir}/diff_peak_calling/merge_peak/mspc", mode: 'link', overwrite: true
    
    input:
    file peak_bed from mspc_merge_diffpeak_bed.collect()
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "diffmspc*.bed" into mspc_diffmerge_bed_for_annotate

    when:
    !params.skip_mspc && !params.skip_diffpeakCalling

    shell:
    mspc_directory = baseDir + "/bin/mspc_v3.3"
    treated_situation_startpoint = TREATED_SITUATION_STARTPOINT
    '''
    for bed_file in *.bed
    do
        #Scientific notation converted to numbers
        cat $bed_file | awk 'BEGIN{FS="\t";OFS="\t"}NR>1{print $1,$2*1,$3*1,$1":"$2"-"$3,-log($5)/log(10)}' | sortBed -i - >  ${bed_file/.bed/_sort.bed} 
    done

    ln -s !{mspc_directory}/* ./
    MAX_SITUATION=$(awk -F, '{if(NR>1)print int($3)}' !{formatted_designfile} | sort -r | head -1)
    for ((i=1;i<!{treated_situation_startpoint};i++))
    do
        for ((j=i+1;j<=$MAX_SITUATION;j++))
        do
            count=$(ls *situation_${i}__${j}*sort.bed | wc -w)
            if [ $count -gt 1 ]; then
                ls *situation_${i}__${j}*sort.bed | awk '{ORS=" "}{print "-i",$0}'| awk '{print "dotnet CLI.dll",$0,"-r Tec -w 1E-4 -s 1E-8 > situation_'${i}'_'${j}'.log"}' | bash
                mv */ConsensusPeaks.bed diffmspc_situation_${i}_${j}.bed
            else
                ln *situation_${i}__${j}*sort.bed diffmspc_situation_${i}_${j}.bed
            fi
        done
    done
    count=$( ls diffmspc*.bed | wc -w)
    if [ $count -gt 1 ]; then
        ls diffmspc*.bed | awk '{ORS=" "}{print "-i",$0}'| awk '{print "dotnet CLI.dll",$0,"-r Tec -w 1E-4 -s 1E-8 > situation_diffmerged.log "}' | bash
        mv */ConsensusPeaks.bed diffmspc_merged_peaks.bed
    else
        ln diffmspc*.bed diffmspc_merged_peaks.bed
    fi

    '''
}
process PeakMergeBYbedtools {
    publishDir "${params.outdir}/peak_calling/merge_peak/bedtools", mode: 'link', overwrite: true
    
    input:
    file peak_bed from bedtools_merge_peak_bed.collect()
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "*merged_peaks.bed" into bedtools_merge_bed_for_annotate

    when:
    !params.skip_bedtools && !params.skip_peakCalling

    shell:
    //Skip Peak Calling Tools Setting
    skip_macs2 = params.skip_macs2
    skip_metpeak = params.skip_metpeak
    skip_matk = params.skip_matk
    '''
    if [ !{skip_macs2} == "false" ]; then 
        cat macs2*peaks.narrowPeak |awk '{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > macs2_all_peaks.bed
        sortBed -i macs2_all_peaks.bed |mergeBed -i - -c 4,4 -o collapse,count | awk '$5>1{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > macs2_merged_peaks.bed
        fi
    if [ !{skip_metpeak} == "false" ]; then 
        cat metpeak*.bed | bed12ToBed6 -i |awk '{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > metpeak_all_peaks.bed
        sortBed -i metpeak_all_peaks.bed |mergeBed -i - -c 4,4 -o collapse,count | awk '$5>1{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > metpeak_merged_peaks.bed
        fi    
    if [ !{skip_matk} == "false" ]; then 
        cat MATK*.bed| awk '{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > MATK_all_peaks.bed
        sortBed -i MATK_all_peaks.bed |mergeBed -i - -c 4,4 -o collapse,count | awk '$5>1{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > MATK_merged_peaks.bed
        fi   
    cat *_all_peaks.bed | sortBed -i - |mergeBed -i - -c 4,4 -o collapse,count | awk '$5>1{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > bedtools_merged_peaks.bed
    '''
}
process DiffPeakMergeBYbedtools {
    publishDir "${params.outdir}/peak_calling/merge_peak/bedtools", mode: 'link', overwrite: true
    
    input:
    file peak_bed from bedtools_merge_diffpeak_bed.collect()
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "*merged_peaks.bed" into bedtools_diffmerge_bed_for_annotate

    when:
    !params.skip_bedtools && !params.skip_peakCalling

    shell:
    //Skip Differential Peak Calling Tools Setting
    skip_metdiff = params.skip_metdiff
    skip_diffmatk = params.skip_diffmatk
    '''
    if [ !{skip_metdiff} == "false" ]; then 
        cat metdiff*.bed |awk '{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > metdiff_all_peaks.bed
        sortBed -i metdiff_all_peaks.bed |mergeBed -i - -c 4,4 -o collapse,count | awk '$5>1{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > metdiff_merged_peaks.bed
        fi
    if [ !{skip_diffmatk} == "false" ]; then 
        cat diffMATK*.bed | bed12ToBed6 -i |awk '{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > diffMATK_all_peaks.bed
        sortBed -i diffMATK_all_peaks.bed |mergeBed -i - -c 4,4 -o collapse,count | awk '$5>1{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > diffMATK_merged_peaks.bed
        fi
    cat *_all_peaks.bed | sortBed -i - |mergeBed -i - -c 4,4 -o collapse,count | awk '$5>1{print $1"\t"$2"\t"$3"\t"$1":"$2"-"$3}' > diffbedtools_merged_peaks.bed
    '''
}

process MotifSearching {
    publishDir "${params.outdir}/merge/motif", mode: 'link', overwrite: true
    
    input:
    file peak_bed from bed_for_motif_searching.collect()
    file diffpeak_bed from diffbed_for_motif_searching.collect()
    file macs2_summit from macs2_summits.collect()
    file formatted_designfile from formatted_designfile.collect()
    file fasta
    file gtf

    output:
    file "*_dreme" into motif_results

    when:
    !params.skip_dreme

    script:
    treated_situation_startpoint = TREATED_SITUATION_STARTPOINT
    """
    bash $baseDir/bin/motif_by_dreme.sh $fasta $gtf ${task.cpus}
    """
}

Channel
    .from()
    .concat(
            bam_for_counting_peaks, metpeak_for_annotate, macs2_for_annotate, matk_for_annotate,
            metdiff_for_annotate, diffmatk_for_annotate,
            mspc_merge_bed_for_annotate, mspc_diffmerge_bed_for_annotate,
            bedtools_merge_bed_for_annotate, bedtools_diffmerge_bed_for_annotate
        )
    .set { annotate_collection }

process BedAnnotatedAndCounted{
    publishDir "${params.outdir}/merge/annotation", mode: 'link', overwrite: true
    
    input:
    file annotate_file from annotate_collection.collect()
    file formatted_designfile from formatted_designfile.collect()
    file fasta
    file gtf

    output:
    //file "*annotatedbyhomer.bed" into homer_annotated
    file "annotatedbyxy/*.anno.txt" into xy_annotated_for_arranging
    file "*.count" into peaks_count_for_arranged
    file "annotatedbyxy/*" into  xy_annotated_results
    when:
    true

    shell:
    annotated_script_dir = baseDir + "/bin"
    //Skip Peak Calling Tools Setting
    skip_macs2 = params.skip_macs2
    skip_metpeak = params.skip_metpeak
    skip_matk = params.skip_matk
    //Skip Differential Peak Calling Tools Setting
    skip_metdiff = params.skip_metdiff
    skip_diffmatk = params.skip_diffmatk
    skip_bedtools = params.skip_bedtools
    skip_mspc = params.skip_mspc
    '''
    # Annotation Peaks
    ln !{annotated_script_dir}/intersec.pl ./
    ln !{annotated_script_dir}/m6A_annotate_forGTF_xingyang2.pl ./
    bash !{baseDir}/bin/annotation.sh !{fasta} !{gtf} !{task.cpus}

    # Count Peaks for different Peak Calling Tools and different Aligners Tools
    ## Define the list of used aligner tools
    flag_tophat2=$(if [ !{skip_tophat2} == "false" ]; then echo "tophat2" ; fi)
    flag_hisat2=$(if [ !{skip_hisat2} == "false" ]; then echo "hisat2" ; fi)
    flag_bwa=$(if [ !{skip_bwa} == "false" ]; then echo "bwa" ; fi)
    flag_star=$(if [ !{skip_star} == "false" ]; then echo "star" ; fi)
    flag_aligners=$(if [ !{skip_aligners} == "true" ]; then echo "aligners" ; fi)
    Aligner_tools_list=$(echo $flag_tophat2 $flag_hisat2 $flag_bwa $flag_star $flag_aligners)
    
    ## Define the list of peak calling tools
    flag_macs2=$(if [ !{skip_macs2} == "false" ]; then echo "macs2" ; fi)
    flag_metpeak=$(if [ !{skip_metpeak} == "false" ]; then echo "metpeak" ; fi)
    flag_MATK=$(if [ !{skip_matk} == "false" ]; then echo "MATK" ; fi)
    flag_metdiff=$(if [ !{skip_metdiff} == "false" ]; then echo "metdiff" ; fi)
    flag_diffMATK=$(if [ !{skip_diffmatk} == "false" ]; then echo "diffMATK" ; fi)
    flag_bedtools=$(if [ !{skip_bedtools} == "false" ]; then echo "bedtools" ; fi)
    flag_mspc=$(if [ !{skip_mspc} == "false" ]; then echo "mspc diffmspc" ; fi)
    Peak_calling_tools_list=$(echo $flag_macs2 $flag_metpeak $flag_MATK $flag_metdiff $flag_diffMATK $flag_bedtools $flag_mspc)
    
    echo ${Aligner_tools_list} > 1.log
    echo ${Peak_calling_tools_list} > 2.log
    for aligners_name in ${Aligner_tools_list};
    do
        for peak_call_name in ${Peak_calling_tools_list};
        do
            echo ${aligners_name} ${peak_call_name}  >>3.log;
            bash !{baseDir}/bin/bed_count.sh ${aligners_name} ${peak_call_name} !{formatted_designfile} !{task.cpus};
        done ;
    done
    '''
}

Channel
    .from()
    .concat( xy_annotated_for_arranging, motif_results, bam_stat_for_normlization, 
        htseq_count_ip_to_arrange ,htseq_count_input_to_arrange, peaks_count_for_arranged 
    )
    .set{ results_arrange }
process AggrangeForM6Aviewer {
    publishDir "${params.outdir}/merge/", mode: 'link', overwrite: true
    
    input:
    file results from results_arrange.collect()
    file formatted_designfile from formatted_designfile.collect()

    output:
    file "m6APipe_results.RDate" into final_results

    when:
    true 

    shell:
    '''
    echo "Unique_Reads" > bam_stat_summary.txt
    for bam_stat in *.bam_stat.txt ;
    do 
        printf ${bam_stat/.bam_stat.txt/_sort.bam}" " >> bam_stat_summary.txt;
        cat ${bam_stat} |grep \(unique\) | awk '{FS=" "}{print $NF}' >> bam_stat_summary.txt ;
    done
    # Count Peaks for different Peak Calling Tools and different Aligners Tools
    ## Define the list of used aligner tools
    flag_tophat2=$(if [ !{skip_tophat2} == "false" ]; then echo "tophat2" ; fi)
    flag_hisat2=$(if [ !{skip_hisat2} == "false" ]; then echo "hisat2" ; fi)
    flag_bwa=$(if [ !{skip_bwa} == "false" ]; then echo "bwa" ; fi)
    flag_star=$(if [ !{skip_star} == "false" ]; then echo "star" ; fi)
    flag_aligners=$(if [ !{skip_aligners} == "true" ]; then echo "aligners" ; fi)
    Aligner_tools_list=$(echo $flag_tophat2 $flag_hisat2 $flag_bwa $flag_star $flag_aligners)
    
    ## Define the list of peak calling tools
    flag_macs2=$(if [ !{skip_macs2} == "false" ]; then echo "macs2" ; fi)
    flag_metpeak=$(if [ !{skip_metpeak} == "false" ]; then echo "metpeak" ; fi)
    flag_MATK=$(if [ !{skip_matk} == "false" ]; then echo "MATK" ; fi)
    flag_metdiff=$(if [ !{skip_metdiff} == "false" ]; then echo "metdiff" ; fi)
    flag_diffMATK=$(if [ !{skip_diffmatk} == "false" ]; then echo "diffMATK" ; fi)
    flag_bedtools=$(if [ !{skip_bedtools} == "false" ]; then echo "bedtools" ; fi)
    flag_mspc=$(if [ !{skip_mspc} == "false" ]; then echo "mspc diffmspc" ; fi)
    Peak_calling_tools_list=$(echo $flag_macs2 $flag_metpeak $flag_MATK $flag_metdiff $flag_diffMATK $flag_bedtools $flag_mspc)
    
    echo ${Aligner_tools_list} > 1.log
    echo ${Peak_calling_tools_list} > 2.log
    for aligners_name in ${Aligner_tools_list};
    do
        for peak_call_name in ${Peak_calling_tools_list};
        do
            echo ${aligners_name} ${peak_call_name}  >>3.log;
           Rscript $baseDir/bin/arranged_results.R ${aligners_name} ${peak_call_name} !{formatted_designfile} !{task.cpus};
        done ;
    done
    '''
}