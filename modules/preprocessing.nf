/*
 * =========================================================
 * WGS/WES Germline Analysis Pipeline - Alignment Module
 * =========================================================
 * Author   : Po-Yu Lin (林伯昱)
 * Institute: Department of Neurology and
 *            Department of Genomic Medicine,
 *            National Cheng Kung University Hospital
 * Contact  : p88124019@gs.ncku.edu.tw
 *
 * Copyright (c) 2026, Po-Yu Lin (林伯昱)
 * 
 *  * This program is free software: you can redistribute it and/or modify
 *  * it under the terms of the GNU General Public License as published by
 *  * the Free Software Foundation, either version 3 of the License, or
 *  * (at your option) any later version.
 *  *
 *  * This program is distributed in the hope that it will be useful,
 *  * but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  * GNU General Public License for more details.
 *  *
 *  * You should have received a copy of the GNU General Public License
 *  * along with this program. If not, see <https://www.gnu.org/licenses/>.
 *  *
 *  * THIRD-PARTY TOOLS NOTICE:
 *  * This pipeline orchestrates third-party tools subject to their own licenses.
 *  * Users of main_research.nf must comply with:
 *  *   - Manta (Illumina): PolyForm Strict License 1.0.0 (non-commercial only)
 *  *   - ExpansionHunter (Illumina): PolyForm Strict License 1.0.0 (non-commercial only)
 *  * See README.md and LICENSE for details.
 *
 * DISCLAIMER: This pipeline is provided "as is" without
 * warranty of any kind. The authors and their institution
 * make no representations or warranties regarding the
 * accuracy, completeness, or suitability of the analysis
 * results for any clinical or research purpose. Users are
 * solely responsible for validating and interpreting all
 * results. This software shall not be held liable for any
 * direct, indirect, or consequential damages arising from
 * its use.
 * =========================================================
 */

process FASTP {
    tag "$meta.id"
    // 實測：RAM 6.4GB，CPU 740%（~8 cores）
    // withName 在 config 有個別設定，label 作為 fallback
    label 'process_medium'

    publishDir "${params.out_dir}/${meta.sample_id}/01_preprocessing", mode: 'copy'

    // INPUT:
    //   meta  - sample metadata map（id, sex）
    //   reads - [R1.fastq.gz, R2.fastq.gz] paired-end reads
    input:
    tuple val(meta), path(reads)

    // OUTPUT:
    //   reads - adapter-trimmed, quality-filtered FASTQ pair
    //   json  - fastp QC metrics（供 MultiQC 使用）
    //   html  - fastp QC HTML report
    output:
    tuple val(meta), path("*.fastp.fastq.gz"), emit: reads
    path "*.json",                             emit: json
    path "*.html",                             emit: html

    script:
    def prefix = "${meta.id}"
    """
    fastp \
        --in1 ${reads[0]} \
        --in2 ${reads[1]} \
        --out1 ${prefix}_1.fastp.fastq.gz \
        --out2 ${prefix}_2.fastp.fastq.gz \
        --json ${prefix}.fastp.json \
        --html ${prefix}.fastp.html \
        --report_title "${prefix}_fastp_report" \
        --thread ${task.cpus} \
        --detect_adapter_for_pe \
        --correction \
        --overrepresentation_analysis \
        --cut_front \
        --cut_tail \
        --cut_mean_quality 20 \
        --length_required 50 \
        --qualified_quality_phred 15 \
        --unqualified_percent_limit 40
    """
}