#!/bin/zsh
# Tokarium.app を作る。
#   scripts/build_app.sh            手元確認用（アドホック署名・このMacのCPU向け）
#   UNIVERSAL=1 scripts/build_app.sh  Apple Silicon と Intel の両方で動くアプリ
#   SIGN_IDENTITY="Developer ID Application: 名前 (TEAMID)" で配布用に署名する
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)/Tokarium"
APP="build/Tokarium.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tokarium"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
if [[ ! -f build/AppIcon.icns ]]; then
  swift scripts/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # 公証に必要な Hardened Runtime とタイムスタンプを付けて署名する
  codesign --force --options runtime --timestamp \
    --entitlements Resources/Tokarium.entitlements --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "作成しました: $APP ($(lipo -archs "$APP/Contents/MacOS/Tokarium"))"
