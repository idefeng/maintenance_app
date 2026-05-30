#!/bin/zsh
set -euo pipefail

# 默认执行保守清理、文件整理和登录项只读报告；如需清理业务资产和交付包，请手动调用 disk_cleanup.py --apply --include-assets。
cd /Users/idefeng/Documents/work
/usr/bin/python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --apply --login-items --organize-files "$@"
