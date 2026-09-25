#!/bin/zsh
# 公開ページ（docs/）の素材を、アプリの描画・音・フォントから作り直す。
#   scripts/make_site_assets.sh
set -euo pipefail
cd "$(dirname "$0")/.."
A=docs/assets
mkdir -p $A/fonts $A/sounds $A/icon
# 魚・装飾のドット絵と、画面の写真
TOKARIUM_SITE=$PWD/$A swift test --filter exportSiteAssets
# ドット絵フォント（SIL OFL）
cp Resources/Fonts/DotGothic16-Regular.ttf Resources/Fonts/OFL.txt $A/fonts/
# BGM と効果音（ページで鳴らすものだけ）
for s in bgm_day sfx_tap sfx_coin sfx_feed sfx_eat sfx_click sfx_sparkle sfx_birth; do
  cp Resources/Sounds/$s.m4a $A/sounds/
done
# アイコン
if [[ ! -d build/AppIcon.iconset ]]; then swift scripts/make_icon.swift build/AppIcon.iconset; fi
cp build/AppIcon.iconset/icon_256x256.png $A/icon/icon-256.png
cp build/AppIcon.iconset/icon_32x32.png $A/icon/favicon-32.png
touch docs/.nojekyll
echo "作成しました: $A"
