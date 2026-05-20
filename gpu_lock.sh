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

# gpu_lock.sh - 使用 flock 保證原子性的 GPU 分配腳本
# 用法：eval $(bash gpu_lock.sh [N]) → 設定 MY_GPUS 和 CUDA_VISIBLE_DEVICES
# N：要鎖定的 GPU 數量（預設 1）
 
GPU_LOCK_DIR="/raid/DGM/gpu_locks"
GPU_IDS=(10 11 12 13 14 15)
MUTEX_FILE="/raid/DGM/gpu_locks/nxf_gpu_mutex"
N="${1:-1}"   # 要一次鎖定的 GPU 數量，預設 1
 
mkdir -p "${GPU_LOCK_DIR}"
touch "${MUTEX_FILE}"
 
while true; do
    # flock 臨界區內只輸出一行：逗號分隔的 GPU 清單，或 NONE
    # 所有 debug 訊息都導向 stderr（>&2），避免污染 RESULT
    RESULT=$(
        flock -x "${MUTEX_FILE}" bash -c "
            GPU_LOCK_DIR=\"/raid/DGM/gpu_locks\"
            GPU_IDS=(10 11 12 13 14 15)
            N=${N}
 
            FREE_GPUS=()
            for GPU_ID in \"\${GPU_IDS[@]}\"; do
                LOCK_FILE=\"\${GPU_LOCK_DIR}/gpu_\${GPU_ID}.lock\"
                if [ ! -f \"\${LOCK_FILE}\" ]; then
                    FREE_GPUS+=(\"\${GPU_ID}\")
                fi
            done
 
            if [ \${#FREE_GPUS[@]} -lt \${N} ]; then
                echo 'NONE'
                exit 0
            fi
 
            LOCKED=()
            for i in \$(seq 0 \$(( N - 1 ))); do
                GPU_ID=\"\${FREE_GPUS[\$i]}\"
                echo \$\$ > \"\${GPU_LOCK_DIR}/gpu_\${GPU_ID}.lock\"
                LOCKED+=(\"\${GPU_ID}\")
            done
 
            IFS=','; echo \"\${LOCKED[*]}\"
        "
    )
 
    # RESULT 現在只有一行：逗號分隔的 GPU 清單（如 "10,11"）或 "NONE"
    if [ "${RESULT}" != "NONE" ] && [ -n "${RESULT}" ]; then
        echo "export MY_GPUS=${RESULT}"
        echo "export CUDA_VISIBLE_DEVICES=${RESULT}"
        echo "[gpu_lock] PID $$ 取得 GPU ${RESULT}" >&2
        exit 0
    fi
 
    echo "[gpu_lock] PID $$ 等待 ${N} 張空閒 GPU..." >&2
    sleep 15
done