#!/bin/zsh
set -euo pipefail

# 构建可双击启动的 macOS .app 包，SwiftPM 仍然是唯一编译入口。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="MaintenanceApp"
BUNDLE_IDENTIFIER="com.idefeng.maintenanceapp"
DIST_ROOT="$TOOL_ROOT/dist"
APP_BUNDLE="$DIST_ROOT/$APP_NAME.app"
INSTALL_BUNDLE="/Applications/$APP_NAME.app"
CONTENTS_ROOT="$APP_BUNDLE/Contents"
MACOS_ROOT="$CONTENTS_ROOT/MacOS"
RESOURCES_ROOT="$CONTENTS_ROOT/Resources"
INFO_PLIST="$TOOL_ROOT/Resources/AppBundle/Info.plist"
ICON_PATH="$TOOL_ROOT/.build/generated/$APP_NAME.icns"
INSTALL=false

for arg in "$@"; do
  case "$arg" in
    --install)
      INSTALL=true
      ;;
    *)
      echo "未知参数: $arg" >&2
      echo "用法: $0 [--install]" >&2
      exit 2
      ;;
  esac
done

cd "$TOOL_ROOT"
python3 "$SCRIPT_DIR/generate_app_icon.py" >/dev/null
swift build -c release --product "$APP_NAME"

EXECUTABLE_PATH="$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME"
if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "找不到可执行文件: $EXECUTABLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_ROOT" "$RESOURCES_ROOT"
cp "$EXECUTABLE_PATH" "$MACOS_ROOT/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS_ROOT/Info.plist"
cp "$ICON_PATH" "$RESOURCES_ROOT/$APP_NAME.icns"
printf "APPL????" > "$CONTENTS_ROOT/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_BUNDLE" >/dev/null
fi

if [[ "$INSTALL" == "true" ]]; then
  if [[ -e "$INSTALL_BUNDLE" ]]; then
    EXISTING_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$INSTALL_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$EXISTING_IDENTIFIER" != "$BUNDLE_IDENTIFIER" ]]; then
      echo "拒绝覆盖 Bundle ID 不匹配的应用: $INSTALL_BUNDLE ($EXISTING_IDENTIFIER)" >&2
      exit 1
    fi
    rm -rf "$INSTALL_BUNDLE"
  fi
  cp -R "$APP_BUNDLE" "$INSTALL_BUNDLE"
  echo "$INSTALL_BUNDLE"
fi

echo "$APP_BUNDLE"
