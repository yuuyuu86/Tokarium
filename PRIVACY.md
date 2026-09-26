# Tokarium プライバシーについて

[English](#english)

Tokarium は、あなたのMacの中だけで動くゲームです。ゲームのデータを外部へ送信しません。有料のAI APIも呼び出しません。

外部と通信するのは次の2つだけです。

- **アップデートの確認**: 配信先（appcast.xml）に新しい版があるかを問い合わせます。送るのはアプリ名と版を含む通常の問い合わせだけで、Macの詳しい情報は送りません。設定で自動確認をオフにできます。
- **不具合の報告**: あなたが「不具合を報告」を選んだときだけ、報告内容を入れたブラウザ（GitHub）またはメールを開きます。送信するかどうかは、内容を確認したうえであなたが決めます。自動では送りません。

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
- ウィジェット用の水槽の画像と状態（`widget/`）
- スクリーンセーバー用の水槽の状態（`saver-scene.json`）
- 自動バックアップ（`backups/`、1日1回・7世代）

「iCloud Drive で同期」をオンにしたときは、水槽のデータ（`game.json`）と Mac ごとに得たコインの数を、あなたの iCloud Drive の `Tokarium` フォルダにも保存します。水槽の写真は、撮ったときだけ `~/Pictures/Tokarium` に保存します。スクリーンセーバーは、設定で入れたときだけ `~/Library/Screen Savers/Tokarium.saver` に置きます。

AIとの会話本文、APIキー、パスワード、ブラウザのCookieは保存しません。

## ログ

`~/Library/Logs/Tokarium/tokarium.log` に、起動や読み取りエラーの記録を残します（ホームフォルダのパスとユーザー名は伏せます）。会話本文は書きません。

## 通知

魚が危険な状態になったとき、病気になったとき、稚魚が生まれたとき、実績を達成したときに、macOSの通知を出します。お世話のリマインドをオンにすると、決まった時刻にも通知します。設定でオフにできます。

## データの削除

アプリを削除したうえで `~/Library/Application Support/Tokarium/` フォルダを削除すると、Tokarium のデータはすべて消えます。Homebrew で入れた場合は `brew uninstall --zap --cask tokarium` で、ログやスクリーンセーバーを含めてまとめて消せます。AIアプリの利用記録には影響しません。

---

<a id="english"></a>

# Privacy (English)

Tokarium is a game that runs entirely on your Mac. It never sends your game data anywhere and never calls paid AI APIs.

It connects to the network in only two cases:

- **Update checks:** it asks the update feed (appcast.xml) whether a new version exists. This is an ordinary request that includes the app name and version, not detailed information about your Mac. You can turn off automatic checks in Settings.
- **Bug reports:** only when you choose "Report a Problem…", it opens your browser (GitHub) or email with the report filled in. You review it and decide whether to send it. Nothing is sent automatically.

## What it reads

It reads, read-only, the usage records of the AI apps you allow during setup or later in Settings: Claude Code, Claude desktop (Cowork), Codex (CLI and desktop), Gemini CLI, Qwen Code, OpenCode, GitHub Copilot CLI and Ollama. From these records it uses only token counts, times and IDs to avoid double counting (for Ollama, which has no token counts, it estimates tokens from the length of messages).

The record files also contain your conversations, but Tokarium never uses, stores or sends them, and never changes the records.

## What it stores

Only the following, in `~/Library/Application Support/Tokarium/`:

- Your tank, fish, decorations, coins spent and first launch time (`game.json`)
- The coin ledger: token counts and record counts per source, latest record times, IDs to avoid double counting, and read positions (`usage-ledger.json`)
- Settings (`settings.json`)
- Tank images and status for the widget (`widget/`) and the screen saver (`saver-scene.json`)
- Automatic backups (`backups/`, daily, 7 generations)

If you turn on iCloud Drive sync, your tank data and the coins earned on each Mac are also saved to the `Tokarium` folder in your iCloud Drive. Photos of your tank are saved to `~/Pictures/Tokarium` only when you take one.

Tokarium never stores your AI conversations, API keys, passwords or browser cookies.

## Logs

`~/Library/Logs/Tokarium/tokarium.log` records launches and read errors, with your home folder path and user name masked. Conversations are never written to it.

## Notifications

Tokarium shows macOS notifications when a fish is in danger or sick, when fry are born and when you earn an achievement. If you turn on care reminders, it also notifies you at set times. You can turn these off in Settings.

## Deleting your data

Delete the app, then delete `~/Library/Application Support/Tokarium/` to remove all Tokarium data. If you installed with Homebrew, `brew uninstall --zap --cask tokarium` removes everything, including logs and the screen saver. Your AI apps' usage records are not affected.
