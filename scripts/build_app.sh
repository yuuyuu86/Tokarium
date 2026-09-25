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
BINDIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"
APP="build/Tokarium.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BINDIR/Tokarium" "$APP/Contents/MacOS/Tokarium"
# 自動アップデート用の Sparkle を同梱する
ditto "$BINDIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Tokarium" 2>/dev/null || true
cp Resources/Info.plist "$APP/Contents/Info.plist"
# ドット絵フォント（DotGothic16, SIL OFL）
ditto Resources/Fonts "$APP/Contents/Resources/Fonts"
# BGM と効果音（scripts/audio/ で MIDI から作ったオリジナル）
ditto Resources/Sounds "$APP/Contents/Resources/Sounds"
# 同梱しているソフトウェアのライセンス
ditto Resources/Licenses "$APP/Contents/Resources/Licenses"
# 翻訳（ja / en）
for lproj in Resources/*.lproj(N); do
  ditto "$lproj" "$APP/Contents/Resources/$(basename "$lproj")"
done
# アップデートの配信先と公開鍵（scripts/release.sh から渡す）
if [[ -n "${SPARKLE_FEED_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL $SPARKLE_FEED_URL" "$APP/Contents/Info.plist"
fi
if [[ -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
fi
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
# ウィジェット（WidgetKit の拡張。サンドボックス必須）
WIDGET="$APP/Contents/PlugIns/TokariumWidget.appex"
mkdir -p "$WIDGET/Contents/MacOS" build/widget
WIDGET_ARCHS=(arm64)
[[ "${UNIVERSAL:-0}" == "1" ]] && WIDGET_ARCHS=(arm64 x86_64)
WIDGET_BINS=()
for arch in "${WIDGET_ARCHS[@]}"; do
  xcrun swiftc -parse-as-library -application-extension -target "$arch-apple-macos14.0" -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -O -module-name TokariumWidget -o "build/widget/TokariumWidget-$arch" Widget/TokariumWidget.swift -framework WidgetKit -framework SwiftUI
  WIDGET_BINS+=("build/widget/TokariumWidget-$arch")
done
lipo -create "${WIDGET_BINS[@]}" -output "$WIDGET/Contents/MacOS/TokariumWidget"
cp Widget/Info.plist "$WIDGET/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$WIDGET/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$WIDGET/Contents/Info.plist"
fi

# スクリーンセーバー（水槽の描画のコードを共有する別のバンドル）
SAVER="$APP/Contents/Resources/Tokarium.saver"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources" build/saver
SAVER_SRC=(Sources/Tokarium/Art/*.swift Sources/Tokarium/Game/Catalog.swift Sources/Tokarium/Game/GameState.swift
           Sources/Tokarium/Game/Simulation.swift Sources/Tokarium/Game/Progress.swift Sources/Tokarium/Game/Ecology.swift
           Sources/Tokarium/Game/Events.swift Sources/Tokarium/Render/AquariumStyle.swift Sources/Tokarium/Render/PixelSprites.swift
           Sources/Tokarium/Render/SwimEngine.swift Saver/TokariumSaver.swift)
SAVER_BINS=()
for arch in "${WIDGET_ARCHS[@]}"; do
  xcrun swiftc -parse-as-library -swift-version 5 -target "$arch-apple-macos14.0" -sdk "$(xcrun --show-sdk-path --sdk macosx)" -O \
    -module-name TokariumSaver -emit-library -Xlinker -bundle -o "build/saver/TokariumSaver-$arch" "${SAVER_SRC[@]}" \
    -framework ScreenSaver -framework SwiftUI
  SAVER_BINS+=("build/saver/TokariumSaver-$arch")
done
lipo -create "${SAVER_BINS[@]}" -output "$SAVER/Contents/MacOS/TokariumSaver"
cp Saver/Info.plist "$SAVER/Contents/Info.plist"
[[ -f build/AppIcon.icns ]] && cp build/AppIcon.icns "$SAVER/Contents/Resources/thumbnail.icns"

if [[ ! -f build/AppIcon.icns ]]; then
  swift scripts/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # 公証に必要な Hardened Runtime とタイムスタンプを付けて、内側から順に署名する
  SIGN=(codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY")
  "${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
  "${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
  "${SIGN[@]}" "$SPARKLE"
  "${SIGN[@]}" --entitlements Widget/TokariumWidget.entitlements "$WIDGET"
  "${SIGN[@]}" "$SAVER"
  "${SIGN[@]}" --entitlements Resources/Tokarium.entitlements "$APP"
else
  # 内側から順に署名する（--deep だとウィジェットのサンドボックス設定が消える）
  codesign --force --deep --sign - "$SPARKLE"
  codesign --force --sign - --entitlements Widget/TokariumWidget.entitlements "$WIDGET"
  codesign --force --sign - "$SAVER"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "作成しました: $APP ($(lipo -archs "$APP/Contents/MacOS/Tokarium"))"
