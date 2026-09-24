# Tokarium プライバシーについて

Tokarium は、あなたのMacの中だけで動くゲームです。サーバーはなく、データを外部へ送信しません。有料のAI APIも呼び出しません。

## 読み取るもの

初回起動時とあとから設定画面で、あなたが許可したAIアプリの利用記録だけを、読み取り専用で読みます。

| 対応元 | 場所 | 使う項目 |
|---|---|---|
| Claude Code | `~/.claude/projects` など | 応答ごとのトークン数・時刻・応答ID |
| Claude デスクトップ（Cowork） | `~/Library/Application Support/Claude/local-agent-mode-sessions` | 応答ごとのトークン数・時刻・応答ID |
| Codex（CLI・デスクトップ） | `~/.codex/sessions` など | トークン数・時刻・セッションID・利用枠の消費率 |
| Gemini CLI / Qwen Code | `~/.gemini/tmp`, `~/.qwen/tmp` | 応答ごとのトークン数・時刻・ID |
| OpenCode | `~/.local/share/opencode` | トークン数・時刻・メッセージID |
| GitHub Copilot CLI | `~/.copilot/session-state` | トークン数・時刻・イベントID |
| Ollama | `~/Library/Application Support/Ollama/db.sqlite` | メッセージの文字数・時刻・行番号 |

記録ファイルには会話の本文も含まれますが、Tokarium は本文を保存・送信しません。記録を書き換えることもありません。

## 保存するもの

`~/Library/Application Support/Tokarium/` に次のものだけを保存します。

- 水槽・魚・装飾・コインの使用量・初回起動日時（`game.json`）
- コイン計算の帳簿: 取得元ごとのトークン数と件数、最新の記録時刻、重複を防ぐためのID、読み取り位置（`usage-ledger.json`）
- 設定（`settings.json`）

AIとの会話本文、APIキー、パスワード、ブラウザのCookieは保存しません。

## 通知

魚が危険な状態になったとき、病気になったとき、稚魚が生まれたときに、macOSの通知を出します。設定でオフにできます。

## データの削除

アプリを削除したうえで `~/Library/Application Support/Tokarium/` フォルダを削除すると、Tokarium のデータはすべて消えます。AIアプリの利用記録には影響しません。
