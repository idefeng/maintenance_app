#!/bin/zsh
set -euo pipefail

# 安装每周保守磁盘清理任务。
PLIST_SOURCE="/Users/idefeng/Documents/work/tools/disk_cleanup/launchd/com.idefeng.disk-cleanup.plist"
PLIST_TARGET="${HOME}/Library/LaunchAgents/com.idefeng.disk-cleanup.plist"

mkdir -p "${HOME}/Library/LaunchAgents"
cp "${PLIST_SOURCE}" "${PLIST_TARGET}"
launchctl unload "${PLIST_TARGET}" 2>/dev/null || true
launchctl load "${PLIST_TARGET}"
launchctl print "gui/$(id -u)/com.idefeng.disk-cleanup" || true
