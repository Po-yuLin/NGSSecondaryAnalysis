#!/usr/bin/env nextflow

/*
 * =========================================================
 * WGS/WES Germline Analysis Pipeline
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
 
nextflow.enable.dsl = 2

if (!params.input_csv)   { error "錯誤：請提供 --input_csv 參數" }
if (!params.pon_out_dir) { error "錯誤：請提供 --pon_out_dir 參數" }

// 引入所有外部模組 (請確認相對路徑是否正確)
include { FASTP }             from './modules/preprocessing.nf'
include { PARABRICKS_FQ2BAM } from './modules/alignment.nf'
include { 
    PREP_GATK_INTERVALS; 
    PREP_CNVKIT_BEDS; 
    COLLECT_GATK_COUNTS;   // <- GATK 專用
    COLLECT_CNVKIT_COV;    // <- CNVkit 專用
    CNVKIT_REFERENCE; 
    FILTER_INTERVALS; 
    PLOIDY_COHORT; 
    SCATTER_INTERVALS; 
    GCNV_COHORT 
} from './modules/pon.nf'

workflow {

    // 1. 讀取樣本清單
    ch_input = Channel
        .fromPath(params.input_csv)
        .splitCsv(header: true)
        .map { row ->
            def meta  = [id: row.sample, sample_id: row.sample, sex: row.sex ?: 'unknown', lane: 'L001']
            def reads = [file(row.fastq_1), file(row.fastq_2)]
            return [meta, reads]
        }

    // 2. 宣告參考基因體與相關索引檔案 Channel
    ch_fasta        = file(params.fasta)
    ch_fasta_fai    = file("${params.fasta}.fai")
    ch_fasta_dict   = file(params.fasta.replace('.fasta', '.dict'))
    ch_wes_targets  = file(params.wes_targets)

    // BWA 索引
    ch_bwa_amb = file("${params.fasta}.amb")
    ch_bwa_ann = file("${params.fasta}.ann")
    ch_bwa_bwt = file("${params.fasta}.bwt")
    ch_bwa_pac = file("${params.fasta}.pac")
    ch_bwa_sa  = file("${params.fasta}.sa")

    // 已知變異點 (依據你之前的設定對齊 4 個 knownSites)
    ch_dbsnp      = file(params.dbsnp)
    ch_dbsnp_tbi  = file("${params.dbsnp}.tbi")
    ch_indel      = file(params.known_indels)
    ch_indel_tbi  = file("${params.known_indels}.tbi")
    ch_indel2     = file(params.known_indels2)
    ch_indel2_tbi = file("${params.known_indels2}.tbi")
    ch_snps       = file(params.known_snps)
    ch_snps_tbi   = file("${params.known_snps}.tbi")
    
    // =========================================================
    // PON 專屬 Reference 與過濾神兵 Channel
    // =========================================================
    ch_ploidy_priors = file(params.contig_ploidy_priors)
    ch_blacklist     = file(params.blacklist_bed)
    ch_mappability   = file(params.mappability_bed)
    ch_segdup        = file(params.segdup_bed)

    // =========================================================
    // 執行管線
    // =========================================================

    // A. 前處理與比對 (呼叫既有常規模組)
    FASTP(ch_input)
    
    PARABRICKS_FQ2BAM(
        FASTP.out.reads,
        ch_fasta, ch_fasta_fai, ch_fasta_dict,
        ch_bwa_amb, ch_bwa_ann, ch_bwa_bwt, ch_bwa_pac, ch_bwa_sa,
        ch_dbsnp, ch_dbsnp_tbi,
        ch_indel, ch_indel_tbi,
        ch_indel2, ch_indel2_tbi,
        ch_snps, ch_snps_tbi
    )

    // B. 準備區間與 BED 檔案 (PON 專用)
    PREP_GATK_INTERVALS(
        ch_fasta, 
        ch_fasta_fai, 
        ch_fasta_dict, 
        ch_wes_targets, 
        ch_blacklist,
        ch_mappability,
        file("${params.mappability_bed}.tbi"),
        ch_segdup,
        file("${params.segdup_bed}.tbi")
    )
    PREP_CNVKIT_BEDS(ch_fasta, ch_fasta_fai, ch_wes_targets)

    // C1. 收集深度資訊 (GATK 專用)
    COLLECT_GATK_COUNTS(
        PARABRICKS_FQ2BAM.out.alignment_bundle,
        ch_fasta,
        ch_fasta_fai,
        ch_fasta_dict,
        PREP_GATK_INTERVALS.out.preprocessed
    )

    // C2. 收集深度資訊 (CNVkit 專用)
    COLLECT_CNVKIT_COV(
        PARABRICKS_FQ2BAM.out.alignment_bundle,
        PREP_CNVKIT_BEDS.out.target_bed,
        PREP_CNVKIT_BEDS.out.antitarget_bed
    )

    // D. 建立 CNVkit Reference (收集所有樣本結果執行)
    CNVKIT_REFERENCE(
        ch_fasta,
        ch_fasta_fai,
        COLLECT_CNVKIT_COV.out.cnvkit_t_cov.collect(), // <- 換成新的輸出通道
        COLLECT_CNVKIT_COV.out.cnvkit_a_cov.collect()  // <- 換成新的輸出通道
    )

    // E. 建立 GATK gCNV Cohort Model
    ch_gatk_counts = COLLECT_GATK_COUNTS.out.gatk_counts.collect() // <- 換成新的輸出通道
    
    FILTER_INTERVALS(
        ch_gatk_counts, 
        PREP_GATK_INTERVALS.out.preprocessed,
        PREP_GATK_INTERVALS.out.annotated)
    
    PLOIDY_COHORT(
        ch_gatk_counts,
        FILTER_INTERVALS.out.intervals,
        ch_ploidy_priors
    )

    // F. 將基因體切成多個碎塊，平行丟給 GCNV_COHORT 執行
    SCATTER_INTERVALS(FILTER_INTERVALS.out.intervals)

    // .withIndex() 給每個 shard 一個唯一 index（0, 1, 2...）
    // 修正 bug：所有 shard 的檔名都叫 scattered.interval_list，
    // GCNV_COHORT 用 baseName 命名輸出目錄時全部相同，39 個 shard 互相覆蓋
    // 用 index 確保每個 shard 輸出到不同目錄（gcnv_model_shard_0, _1, ...）
    // Nextflow channel 不支援 .withIndex()，改用 toList() + flatMap 加 index
    ch_scattered_intervals = SCATTER_INTERVALS.out.scattered_lists
        .flatten()
        .toList()
        .flatMap { shards ->
            shards.withIndex().collect { shard, idx -> [idx, shard] }
        }

    GCNV_COHORT(
        ch_scattered_intervals,
        ch_gatk_counts,
        PREP_GATK_INTERVALS.out.annotated,
        PLOIDY_COHORT.out.ploidy_calls
    )
}