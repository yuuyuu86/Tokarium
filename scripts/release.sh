#!/bin/zsh
# 直接配布用の DMG を作り、署名・公証する。
#
# 事前準備（一度だけ）:
#   1. Apple Developer Program に登録し、「Developer ID Application」証明書をキーチェーンに入れる
#   2. 公証用の認証情報を保存する:
#        xcrun notarytool store-credentials tokarium-notary \
#          --apple-id "あなたのApple ID" --team-id "TEAMID" --password "App用パスワード"
#
# 使い方:
#   3. 自動アップデート用の鍵を作る（秘密鍵はキーチェーンに入り、表示される公開鍵を控える）:
#        .build/artifacts/sparkle/Sparkle/bin/generate_keys
#
#   SIGN_IDENTITY="Developer ID Application: 名前 (TEAMID)" NOTARY_PROFILE=tokarium-notary \
#     SPARKLE_PUBLIC_KEY="控えた公開鍵" VERSION=0.2.0 BUILD_NUMBER=2 scripts/release.sh
#
# 終わると build/updates/ に DMG と appcast.xml ができる。
#   - DMG を GitHub Releases（タグ v$VERSION）にアップロードする
#   - appcast.xml を SUFeedURL の場所（例: GitHub Pages の appcast.xml）に置く
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?SIGN_IDENTITY に Developer ID Application の証明書名を指定してください}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE に notarytool store-credentials で保存した名前を指定してください}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"

swift test
: "${SPARKLE_PUBLIC_KEY:?SPARKLE_PUBLIC_KEY に generate_keys で表示された公開鍵を指定してください}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/yuuyuu86/Tokarium/releases/download/v$VERSION/}"
UNIVERSAL=1 SIGN_IDENTITY="$SIGN_IDENTITY" VERSION="$VERSION" SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" scripts/build_app.sh

DMG="build/Tokarium-$VERSION.dmg"
STAGE="build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Tokarium.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Tokarium" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

echo "公証に送信しています（数分かかります）…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
# アップデートの一覧（appcast.xml）を作る。署名にはキーチェーンの秘密鍵を使う
mkdir -p build/updates
cp "$DMG" build/updates/
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --download-url-prefix "$DOWNLOAD_URL_PREFIX" build/updates
echo "配布用DMGができました: $DMG"
echo "アップデート一覧: build/updates/appcast.xml"
