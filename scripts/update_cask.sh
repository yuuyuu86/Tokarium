#!/bin/zsh
# リリースした版に合わせて、Homebrew の tap（yuuyuu86/homebrew-tap）の cask を更新する。
#   scripts/update_cask.sh 1.0.1
# GitHub Releases に Tokarium-<版>.dmg を置いたあとに実行する。
set -euo pipefail
VERSION="${1:?版を指定してください（例: 1.0.1）}"
URL="https://github.com/yuuyuu86/Tokarium/releases/download/v$VERSION/Tokarium-$VERSION.dmg"
SHA=$(curl -sfL "$URL" | shasum -a 256 | awk '{print $1}')
TAP="$(brew --repository)/Library/Taps/yuuyuu86/homebrew-tap"
[[ -d "$TAP" ]] || brew tap yuuyuu86/tap
git -C "$TAP" pull -q
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/tokarium.rb"
brew style "$TAP/Casks/tokarium.rb"
git -C "$TAP" commit -qam "Tokarium $VERSION"
git -C "$TAP" push -q
echo "cask を $VERSION に更新しました（sha256: $SHA）"
