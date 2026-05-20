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

# gpu_unlock.sh - 釋放 GPU lock
# 用法：bash gpu_unlock.sh <GPU_ID_OR_LIST>
# 支援單張：bash gpu_unlock.sh 10
# 支援多張：bash gpu_unlock.sh 10,11,12,13,14,15

INPUT="$1"
GPU_LOCK_DIR="/raid/DGM/gpu_locks"

# 將逗號分隔的 GPU 清單拆開
IFS=',' read -ra GPU_LIST <<< "${INPUT}"

for GPU_ID in "${GPU_LIST[@]}"; do
    LOCK_FILE="${GPU_LOCK_DIR}/gpu_${GPU_ID}.lock"
    if [ -f "${LOCK_FILE}" ]; then
        rm -f "${LOCK_FILE}"
        echo "[gpu_unlock] GPU ${GPU_ID} 已釋放" >&2
    else
        echo "[gpu_unlock] 警告：找不到 GPU ${GPU_ID} 的 lock" >&2
    fi
done