# Tokarium（トーカリウム）

AIの利用トークンをコインに変えて、ドット絵の水槽を育てる macOS アプリ。
仕様は `Tokarium_仕様書_案.md` を参照。

## ビルドと起動

直接配布（Developer ID 署名＋公証）の DMG を作る手順は `scripts/release.sh` の先頭に書いてある。
Apple Silicon と Intel の両方で動くユニバーサルアプリになる。プライバシーについては `PRIVACY.md`。


```bash
scripts/build_app.sh          # build/Tokarium.app を作る（アドホック署名）
open build/Tokarium.app
swift test                    # 通貨・重複判定・育成ルールのテスト
```

動作確認で本番データを汚したくないときは、保存先を差し替えて起動する:

```bash
TOKARIUM_DATA_DIR=/tmp/tokarium-test build/Tokarium.app/Contents/MacOS/Tokarium
```

保存先（通常）: `~/Library/Application Support/Tokarium/`
- `game.json` 水槽・魚・装飾・使ったコイン・初回起動日時
- `usage-ledger.json` 利用記録の帳簿（件数・時刻・取得元・重複判定ID・トークン数のみ）
- `settings.json` 設定

## 決めたルール

| 項目 | 内容 |
|---|---|
| 通貨換算 | 入力1・出力1・キャッシュ書込0.25・キャッシュ読込0.1 の重みで合計し、10,000トークン＝1コイン。付与上限なし |
| 付与開始 | 初回起動日時より後の記録だけ。時刻がない記録は付与しない |
| 初期状態 | ネオンテトラ1匹・水草・岩・50コイン |
| 育成 | 満腹度は約60時間で0。約3日で「弱っている」、約4日で死亡。水換えは数日に1回 |
| 成長 | よくお世話すると約1週間で稚魚→成魚（お店の魚は若魚から）。成長に合わせて大きく描く |
| 病気 | 水質45未満が続くと発病することがある。薬（25コイン）で治る。きれいな水で自然に治ることも |
| 繁殖 | 元気な成魚が同じ種類で2匹以上・水質60以上で、稚魚が1〜3匹生まれることがある（24時間に1回まで） |
| 寿命 | 種類ごとに120〜365日。85%を過ぎると老齢（ゆっくり泳ぐ）。死因は「弱った・病気・寿命」を記録 |
| 水槽 | 小（魚8・装飾10）→ ふつう300 → 大800 → 特大1500コインで拡張 |
| 死んだ魚 | 底に沈んで灰色になり、お世話画面で「お別れ」すると取り出せる |
| 再開時 | 反映は最大48時間分。再開時の反映だけでは死亡しない（体調5で止まる） |
| 推定値 | Ollama などの推定値は既定ではコインにしない（設定でオン可） |
| 利用枠 | Codex の利用枠の消費率は表示のみ。コインにしない |

## 対応元（`Sources/Tokarium/Usage/Readers.swift`）

| 対応元 | 種類 | 読む場所 |
|---|---|---|
| Claude Code（Claude デスクトップの Code を含む） | 実測 | `~/.claude/projects` ほか |
| Claude デスクトップ（Cowork） | 実測 | `~/Library/Application Support/Claude/local-agent-mode-sessions` |
| Codex（CLI・デスクトップ） | 実測 | `~/.codex/sessions`, `archived_sessions` |
| Gemini CLI / Qwen Code | 実測 | `~/.gemini/tmp`, `~/.qwen/tmp` |
| OpenCode | 実測 | `~/.local/share/opencode`（旧JSON形式と opencode.db） |
| GitHub Copilot CLI | 実測（試験対応） | `~/.copilot/session-state` |
| Ollama | 推定（4文字＝1トークン） | `~/Library/Application Support/Ollama/db.sqlite` |

ChatGPT デスクトップ（会話が暗号化されている）、Claude デスクトップのチャット、Cursor はトークン数が Mac に残らないため非対応。

Claude 系は応答ID＋リクエストIDで、Codex はセッションごとの累計の増分で重複を防ぐ。
対応元を増やすときは `UsageReader` を実装して `UsageReaders.all` に追加する。

## 構成

- `Game/` 魚・装飾のカタログ、状態、育成シミュレーション、`GameStore`
- `Usage/` 利用記録の読み取りと帳簿
- `Render/` ドット絵スプライト、泳ぎの動き、画風（`AquariumStyle` で追加可能）
- `Desktop/` デスクトップ表示（壁紙の上・アイコンの下に置く背景ウィンドウ）
- `UI/` 水槽・お世話・お店・AI利用量・設定・初回設定の画面

## 公開前に残っていること

- 「Developer ID Application」証明書の作成と、`scripts/release.sh` での署名・公証（手元確認用のビルドはアドホック署名）
- デスクトップ表示の実機確認（複数ディスプレイ、Spaces、Stage Manager、フルスクリーン、スリープ復帰）
- Copilot CLI・OpenCode・Gemini CLI の実データでの形式確認（手元に記録がなく未確認）
