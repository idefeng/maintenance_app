#!/bin/zsh
set -euo pipefail

# 安装每周应用残留清理任务，默认使用 launchd 用户域执行。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST_SOURCE="$TOOL_ROOT/launchd/com.idefeng.app-cleanup.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_TARGET="$LAUNCH_AGENTS_DIR/com.idefeng.app-cleanup.plist"

mkdir -p "$LAUNCH_AGENTS_DIR"
cp "$PLIST_SOURCE" "$PLIST_TARGET"

# 先卸载旧配置，再加载新配置，避免 launchd 继续使用过期内容。
/bin/launchctl bootout "gui/$(id -u)" "$PLIST_TARGET" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$(id -u)" "$PLIST_TARGET"
/bin/launchctl enable "gui/$(id -u)/com.idefeng.app-cleanup"

echo "已安装: $PLIST_TARGET"
echo "可用下面命令检查状态:"
echo "launchctl print gui/$(id -u)/com.idefeng.app-cleanup"
