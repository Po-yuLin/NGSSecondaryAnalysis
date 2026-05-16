#!/bin/bash
#
# Copyright (c) 2026, Po-Yu Lin (林伯昱)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# THIRD-PARTY TOOLS NOTICE:
# Users of main_research.nf must comply with:
#   - Manta: PolyForm Strict License 1.0.0 (non-commercial only)
#   - ExpansionHunter: PolyForm Strict License 1.0.0 (non-commercial only)
# See README.md and LICENSE for details.

# ── 自動偵測執行環境 ──────────────────────────────────────
HOSTNAME_SHORT=$(hostname -s)

if [[ "${HOSTNAME_SHORT}" == *"dgx"* ]] || [[ "${HOSTNAME_SHORT}" == "dgx2" ]]; then
    ENV_NAME="DGX-2"
    PIPELINE_BASE="/datalake_Intermediate/pipeline"

    # Java（離線安裝）
    export JAVA_HOME="/opt/java/jdk-17.0.17+10"
    export PATH="${JAVA_HOME}/bin:${PATH}"

    # Nextflow（離線安裝）
    export PATH="/opt/nextflow:${PATH}"
    export NXF_BIN="/opt/nextflow/nextflow-all.jar"
    export NXF_OFFLINE="true"

    # Apptainer bind（DGX-2 的資料路徑）
    export APPTAINER_BIND="/datalake_Intermediate,/datalake_Raw,/raid"

    # Work 目錄（DGX-2 用高速 /raid SSD）
    export NXF_WORK="/raid/DGM/work"
    export NXF_TEMP="/raid/DGM/nextflow_temp"
    export APPTAINER_TMPDIR="/raid/DGM/apptainer_temp"
    export APPTAINER_CACHEDIR="${PIPELINE_BASE}/nextflow_containers"

    # GPU lock 清理
    GPU_LOCK_DIR="/tmp/nxf_gpu_locks"
    if [ -d "${GPU_LOCK_DIR}" ] && [ -n "$(ls ${GPU_LOCK_DIR} 2>/dev/null)" ]; then
        echo "⚠️  發現殘留的 GPU lock，自動清空..."
        rm -f "${GPU_LOCK_DIR}"/*.lock
        echo "✅ GPU lock 已清空"
    fi

    # GPU 設定
    export CUDA_VISIBLE_DEVICES="10,11,12,13,14,15"
    export APPTAINERENV_CUDA_VISIBLE_DEVICES="10,11,12,13,14,15"

else
    ENV_NAME="DGM Server"
    PIPELINE_BASE="/home/pipeline"

    # Java + Nextflow（conda 環境）
    MAMBA_ROOT="/opt/NGS2ndAnalysis/miniforge"
    if [ -f "${MAMBA_ROOT}/bin/activate" ]; then
        source "${MAMBA_ROOT}/bin/activate" "NGS2ndAnalysis"
    else
        echo "❌ 找不到 conda 環境：${MAMBA_ROOT}"
        return 1
    fi
    export JAVA_HOME="${CONDA_PREFIX}"
    export PATH="${JAVA_HOME}/bin:${PATH}"
    export NXF_JAVA_HOME="${CONDA_PREFIX}"

    # Apptainer bind /home → 同時涵蓋：
    #   /home/pipeline/              （本機程式碼、容器、reference）
    #   /home/datalake_Raw/          （原始 FASTQ，samplesheet 直接指這裡）
    #   /home/datalake_Intermediate/ （如需要）
    export APPTAINER_BIND="/home"

    # Work 目錄（全部本機）
    export NXF_WORK="/home/pipeline/work"
    export NXF_TEMP="/home/pipeline/nextflow_temp"
    export APPTAINER_TMPDIR="/home/pipeline/apptainer_temp"       # 執行時暫存
    export APPTAINER_CACHEDIR="/home/pipeline/nextflow_containers" # .sif 容器存放

fi

# ── 共用設定 ──────────────────────────────────────────────
export NXF_HOME="${PIPELINE_BASE}/nextflow_home"
export PIPELINE_CODE="${PIPELINE_BASE}/pipeline_code"
export PIPELINE_REF="${PIPELINE_BASE}/reference/hg38"
export PIPELINE_SIF="${PIPELINE_BASE}/nextflow_containers"
export PIPELINE_CONFIG="${PIPELINE_CODE}/nextflow_main.config"

# ── 確認目錄存在 ──────────────────────────────────────────
mkdir -p "${NXF_WORK}" "${NXF_TEMP}" "${APPTAINER_TMPDIR}"

# ── 顯示環境資訊 ──────────────────────────────────────────
echo "=================================================="
echo "  NGS Secondary Analysis Environment"
echo "  環境：${ENV_NAME}"
echo "  Pipeline：${PIPELINE_CODE}"
echo "  Reference：${PIPELINE_REF}"
echo "  Work：${NXF_WORK}"
echo "=================================================="
java -version 2>&1 | head -1
nextflow -version 2>&1 | grep "version"
echo ""
echo "快速執行範例："
echo "  nextflow -c \${PIPELINE_CONFIG} run \${PIPELINE_CODE}/main.nf \\"
echo "      -profile [dgm|dgx] \\"
echo "      --input_csv /path/to/samplesheet.csv \\"
echo "      --seq_type [WES|WGS] \\"
echo "      --run_gcnv true \\"
echo "      --out_dir /path/to/output \\"
echo "      -resume"
echo "=================================================="