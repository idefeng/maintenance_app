#!/bin/zsh

set -euo pipefail

# 统一计算工具目录，避免 launchd 或手工运行时依赖外部工作目录。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_ROOT="$TOOL_ROOT/runtime/logs"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
LOG_FILE="$LOG_ROOT/file-organizer-$TIMESTAMP.log"
UNIFIED_SCRIPT="/Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py"

PY_ARGS=(--skip-disk-cleanup --organize-files)
APPLY=true
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    # 兼容旧入口的 dry-run 语义：只演练文件整理，不移动文件。
    APPLY=false
  else
    PY_ARGS+=("$arg")
  fi
done
if [[ "$APPLY" == "true" ]]; then
  PY_ARGS+=(--apply)
fi

mkdir -p "$LOG_ROOT"

{
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] 开始执行文件整理"
  /usr/bin/python3 "$UNIFIED_SCRIPT" "${PY_ARGS[@]}"
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] 文件整理执行完成"
} >>"$LOG_FILE" 2>&1
