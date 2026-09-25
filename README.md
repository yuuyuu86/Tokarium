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
| 初期状態 | ネオンテトラ1匹・水草・岩・50コイン・餌20回分 |
| 育成 | 満腹度は約60時間で0。約3日で「弱っている」、約4日で死亡。水換えは数日に1回 |
| 成長 | よくお世話すると約1週間で稚魚→成魚（お店の魚は若魚から）。成長に合わせて大きく描く |
| 餌 | 餌やり1回（全体でも1匹でも）で1つ使う。お店で 10回分5・30回分12・100回分35コイン |
| 病気 | 水質45未満が続くと発病することがある。薬（25コイン）で治る。きれいな水で自然に治ることも |
| 繁殖 | 元気な成魚が同じ種類で2匹以上・水質60以上で、稚魚が1〜3匹生まれることがある（24時間に1回まで） |
| 寿命 | 種類ごとに120〜365日。85%を過ぎると老齢（ゆっくり泳ぐ）。死因は「弱った・病気・寿命」を記録 |
| 水槽 | 小（魚8・装飾10）→ ふつう300 → 大800 → 特大1500コインで拡張 |
| 救済の餌 | コインも餌もなく、いちばん安い餌も買えないときは、1日1回分だけ無料で餌やりできる |
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

## 見た目

- 画風はドット絵のみ（`AquariumStyle` は画風を後から足せる作り）
- 窓いっぱいに水槽を出し、標準のタイトルバーやサイドバーは使わない。操作は下のバー、
  お世話・お店・AI利用量・設定は水槽の上に重なるドット絵のパネル（`UI/PixelUI.swift` の部品を使う）
- 文字は同梱のドット絵フォント DotGothic16（`Resources/Fonts`、SIL Open Font License 1.1、`OFL.txt` 参照）
- 魚 33 種、装飾 34 種。`Game/Catalog.swift` に設計図（体形・ひれ・模様／形のパーツ）で定義し、
  `Art/` がドット絵にする。一部は手描きのスプライト（`Render/PixelSprites.swift`）を優先する
- 全部の見た目を確認するには: `TOKARIUM_SHEET=/tmp swift test --filter renderContactSheet`
- 水槽は1つ。複数ディスプレイでは同じ水槽を表示する

## 遊びの機能

- 図鑑（迎えた数・生まれた数・世代・天寿・色違い・品種）と実績（一部は限定の装飾がもらえる）
- 水をクリックすると魚が寄ってくる。時間帯で光が変わり、夜は魚がゆっくり。季節の浮遊物
- 稚魚がまれに色違いで生まれる。AIをたくさん使った日は宝箱が流れてくる
- よく使うAIごとの記念の魚、日ごとのAI利用グラフ
- 設備（自動給餌器・ろ過フィルター）、お世話のリマインド通知
- 水槽の写真（`~/Pictures/Tokarium`）、バックアップの書き出し・復元、iCloud Drive での同期
- ウィジェット（`Widget/`、WidgetKit の拡張）。アプリが `~/Library/Application Support/Tokarium/widget/` に
  書き出した画像と状態を、サンドボックスの一時的な例外で読む

## やり込み要素

- 品種改良: 魚は色の遺伝子を2つ持ち、両親から1つずつ受け継ぐ（`Game/Genetics.swift`）。7色×組み合わせで1種類につき13品種。
  お店の魚の4匹に1匹は色の遺伝子をかくし持ち、生まれるときにまれに突然変異する。お世話の画面でペアを決めると、その2匹だけで繁殖し、生まれうる品種の確率も見られる
- 飼育員ランク（1〜20, `Game/Keeper.swift`）: 餌やり・水換え（1日の回数に上限）・誕生・成長・図鑑や品種の登録・実績・お題で経験値。
  高い魚・装飾・水槽の拡張・設備はランクが上がるとお店に並ぶ。ランクができる前のデータは記録から経験値を見積もる
- 毎日3つ・毎週2つのお題（`Game/Quests.swift`）。AIの利用量やコインの支払いは数えない。ごほうびは経験値・餌・薬・かけら。かけらは限定の装飾6つと交換
- 隠れた魚5種（`Game/Secrets.swift`）: 条件がそろうと、ときどき迷いこんでくる。図鑑にはヒントだけ
- 殿堂: いちばん長生き・大きい・新しい世代・なかよしの魚と、お別れした魚の思い出（100件まで）
- 称号: 達成した実績を画面上部に表示できる
- 性格6種（くいしんぼう・人なつこい・臆病・元気・のんびり・好奇心旺盛）で泳ぎ方が変わる。なつき度が高いほど、水をたたくと遠くから速く寄ってくる
- レイアウトの評価（`Game/Layout.swift`）: 種類・にぎやかさ・広がり・奥行きと、組み合わせのボーナス8種。配置の編集中に表示
- 記念の魚は、そのAIで 100・1000・5000 コインを得ると3段階でもらえる
- 実績は28種

## 音

- BGM は昼の曲（F メジャー・72BPM・約107秒）と夜の曲（A マイナー・60BPM・128秒）。
  「時間帯で明るさを変える」がオンなら夜7時〜朝5時は夜の曲。切りかえはゆっくり重ねる
- 効果音16種（餌・食べる・水換え・水をたたく・コイン・購入・配置・薬・宝箱・実績・稚魚・死・お別れなど）
- 既定では、水槽の窓が見えているときだけ BGM を流す。稚魚やコインなど、操作によらず起きたことの音も窓が見えているときだけ
- 何も鳴っていないときは音のエンジンを止める（電池のため）。設定の「サウンド」とメニューの「水槽」でオン・オフ（⌥⌘M で BGM）
- 音はすべてオリジナル。Python で MIDI として作曲し（`scripts/audio/compose.py` → `Audio/midi/`）、
  サンプルを使わない自作のシンセで音にする（`scripts/audio/render.py` → `Resources/Sounds/*.m4a`）。
  曲はループの区切りからはみ出した残響を頭に重ねて、つなぎ目なく繰り返す
- 作り直すには: `pip3 install mido numpy` のあと `python3 scripts/audio/compose.py && python3 scripts/audio/render.py`。
  MIDI はふつうの MIDI ファイルなので、DAW で開いて編集してから `render.py` だけ実行してもよい

## 省電力と記録の整理

- 窓が完全に隠れているときは水槽を止める。バッテリー・低電力モードでは 15fps、Mac が熱いときは 10fps（設定でオフにできる）
- 二重付与を防ぐIDは日時つきで持ち、60日より古いものは1日1回整理する。整理した期間より古い記録は数えない

## 安心と使いやすさ

- 自動バックアップ: 1日1回、`backups/` に7世代。水槽のデータが壊れたら別名で残し、いちばん新しい自動バックアップから戻す
- キーボード: ⌘F 餌、⇧⌘W 水換え、⌘P 写真、⌘L 配置の編集、⌘1〜7 画面の切りかえ（メニューの「水槽」）
- VoiceOver: 魚を1匹ずつ（状態・満腹・体調・様子）読み上げ、餌・薬・お気に入りなどの操作ができる
- 「視差効果を減らす」がオンなら、泳ぎをゆっくりにして浮遊物と波紋を出さない

## テスト

`swift test` で、ルール・読み取り・描画に加えて、全画面を日本語・英語・狭い窓で描いて確かめるテストと、
買う・餌・水換え・装飾の配置・お気に入りなど、遊ぶ流れどおりの操作のテストが走る。

## 英語対応

日本語の文言がそのまま翻訳キー。文言を足したら `scripts/translations_en.py` に英訳を追加して
`scripts/make_strings.py` を実行する（訳が足りないと一覧を出して止まる）。
表示言語は設定の「言語」で切り替えられる（再起動で反映）。

## 自動アップデート（Sparkle）と不具合の報告

- アップデートは Sparkle。`scripts/release.sh` が署名済み DMG と `appcast.xml` を作る。
  公開鍵は `Resources/Info.plist` の `SUPublicEDKey`、対になる秘密鍵は開発者のキーチェーンにある（なくすと更新を配れなくなるので `generate_keys -x` で書き出して保管する）
- 配信先は `Resources/Info.plist` の `SUFeedURL`（初期値は GitHub Pages を想定）
- 前回が異常終了だった場合、起動時に報告画面を出す。報告は内容を確認してから
  GitHub Issues（`TKFeedbackURL`）かメール（`TKFeedbackEmail`、空なら非表示）で送る。自動送信はしない
- ログ: `~/Library/Logs/Tokarium/tokarium.log`

## 構成

- `Game/` 魚・装飾のカタログ、状態、育成シミュレーション、`GameStore`
- `Usage/` 利用記録の読み取りと帳簿
- `Art/` 魚と装飾の設計図から形を作り、画風ごとに塗る（`ArtRenderer`）
- `Render/` 泳ぎの動き、背景と水槽の描画（`AquariumStyle`）、手描きのドット絵
- `Desktop/` デスクトップ表示（壁紙の上・アイコンの下に置く背景ウィンドウ）
- `UI/` 水槽・お世話・お店・AI利用量・設定・初回設定・不具合報告の画面
- `App/` 起動処理、アップデート（`Updater`）、ログとクラッシュ検出（`Diagnostics`）、BGM と効果音（`SoundPlayer`）
- `Audio/midi/` BGM と効果音の MIDI（`scripts/audio/` で作曲・音にする）

## 公開前に残っていること

- 「Developer ID Application」証明書の作成と、`scripts/release.sh` での署名・公証（手元確認用のビルドはアドホック署名）
- appcast.xml の置き場所（GitHub Pages など。リポジトリが非公開だと Pages は使えない）
- 不具合報告の送り先: リポジトリが非公開のままだと一般の人は Issue を作れないので、公開するかメールアドレスを設定する
- デスクトップ表示の実機確認（複数ディスプレイ、Spaces、Stage Manager、フルスクリーン、スリープ復帰）
- Copilot CLI・OpenCode・Gemini CLI の実データでの形式確認（手元に記録がなく未確認）

## ライセンス

MIT License（`LICENSE`）。BGM と効果音もこのリポジトリで作ったもので、同じ MIT License。同梱しているソフトウェア:
- Sparkle — MIT License（`Resources/Licenses/Sparkle.txt`）
- DotGothic16 — SIL Open Font License 1.1（`Resources/Licenses/DotGothic16-OFL.txt`）

アプリ内では「Tokarium について」から全文を読める。
