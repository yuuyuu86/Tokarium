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
#   SIGN_IDENTITY="Developer ID Application: 名前 (TEAMID)" NOTARY_PROFILE=tokarium-notary \
#     VERSION=0.1.0 BUILD_NUMBER=1 scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?SIGN_IDENTITY に Developer ID Application の証明書名を指定してください}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE に notarytool store-credentials で保存した名前を指定してください}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"

swift test
UNIVERSAL=1 SIGN_IDENTITY="$SIGN_IDENTITY" VERSION="$VERSION" scripts/build_app.sh

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
echo "配布用DMGができました: $DMG"
