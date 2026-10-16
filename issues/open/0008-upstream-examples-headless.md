---
id: RADEN-0008
status: open
priority: P1
milestone: M1-M4
depends_on: [RADEN-0002, RADEN-0003]
---

# 上流example全8本を追跡し、共通sceneとヘッドレスCLIを作る

## 目的

ライブラリの移植率だけでなく、利用者が実行できるexampleで完成範囲を示す。描画sceneと表示/ファイル/時計のhostを分け、同じsceneをNative CLI、Web、gpuiへ渡す。

## example対応計画

| 上流example | 移植する動作 | core依存 | 最初の検証方法 |
| --- | --- | --- | --- |
| `basic_drawing.rs` | 1280×720の背景と半透明矩形、BMP出力 | 0003 | 生ピクセル完全一致。M1最優先 |
| `gradient_drawing.rs` | Linear Pad/Repeat/Reflect、Radial、Conicの5配置 | 0007 | 同じstop/座標/背景の固定画像 |
| `stroke_drawing.rs` | cap/join、path、半透明stroke | 0006 | 同じ描画順序の固定画像 |
| `blit_clip_pattern_paths.rs` | blit、clip、pattern、拡張Path、matrix | 0004、0007 | 機能別fixture＋全体画像 |
| `animation.rs` | 多数の円、指定size/fps、headless統計 | 0005 | 明示frame index/seedで静止画比較 |
| `tiger/main.rs` | fill/strokeの多数pathを重ねる | 0006、出典確認 | 同じデータ・順序の画像。未確認assetは配布しない |
| `raden_player.rs` | 上流の動的sceneと表示用frame生成 | sceneが使う0005/0006/0007を棚卸し | 固定時刻frameとheadless出力。表示は別host |
| `font_shaping.rs` | liga/kern/clig ON/OFFの対比 | 0011 | 固定font hash/文字列のglyph結果＋画像 |

この表は移植予定であって実装済み一覧ではない。`examples/manifest.json`に各exampleの`core / native_headless / browser / gpui / pixel_parity`を別statusとして持たせる。

## 実装方針

1. 上流exampleの描画関数・定数・描画順を調べてfixture化する。同名だけの別デモを作らず、意図的に変えたUIと変更していないsceneを区別する。デモの初期値とテスト用値が分岐しないよう同じscene builderを使う。
2. 共通sceneは入力parameterとframe indexを受け、MoonBitの描画APIを呼ぶ。壁時計、乱数、ウィンドウイベント、ファイルパスを直接読まない。乱数を使う上流sceneは実際の生成方法を調べ、seedまたは生成済み入力を共有する。
3. Native CLIを作る。提案interfaceは`raden-demo --example basic_drawing --headless --output <dir>`、animationは`--width / --height / --fps / --frame / --seed`を追加する。これは未実装の案であり、実装後に正確な起動commandと出力先をREADMEへ掲載する。
4. 生ピクセルとmetadataを標準成果物にする。BMP writerは独立したcodec/host層としてtop-down、チャンネルmask、stride、alpha扱いを検証する。ブラウザは同じbytesを表示し、ファイルI/Oをcoreへ持ち込まない。
5. animationはテスト時に`time = frame_index / fps`で決定する。real-time実行は同じsceneにホスト時刻から得たframeを渡す。停止、1frame送り、再開、最初へ戻る、サイズ変更を明示的な操作にする。
6. upstream animationの`--duration`によるベンチ方式を調べ、時間制限runと固定frame数runを分ける。性能測定では同じscene/size/frame範囲、compile modeを使い、表示待ち時間と描画時間を分離する。
7. `raw_player`は上流の表示ホストであり、本IssueでMoonBitへ全移植しない。ウィンドウ表示はRADEN-0009/0010で別途提供する。`raden_player`のscene部分だけ完成してもVideoPlayer互換完成と表示しない。
8. tigerは出典台帳と再配布条件を確認した後にデータを変換する。変換script、source hash、command/point数を保存し、変換済みのデータだけを手修正しない。未確認の時は独自の複雑path fixtureでcoreを進め、tigerはblockedのまま残す。

## 成果物

- `examples/manifest.json`、共通scene、headless CLI、BMP/raw出力。
- 各exampleのREADME、起動command、依存、対応target、スクリーンショットと比較状況。
- basic→曲線→stroke/paint→複雑scene→fontという小刻みな実装PR。

## テストと受入条件

1. M1はbasic_drawingだけで成立させる。Native/JSのraw比較とBMP decode後のchannel/寸法を検証する。
2. 全8本をmanifestに登録し、未実装を欠落させない。新しいexampleを上流から取り込む時は固定SHAと表を明示更新する。
3. seed/frame/sizeが同じrunは同じhash、異なる入力は同じrequestとして再利用されないこと。fps=0、巨大frame/size、未知example、出力不能を明示エラーにする。
4. animation停止中はframe/hashが変わらず、1frame送りで期待した入力だけが変化すること。wall clockに依存したgoldenを保存しない。
5. 実際にlibrary APIを呼ぶ独立consumerから各完成exampleを実行する。内部関数に直接依存するテストだけで配布可能としない。
6. 未対応のexampleを成功exitで空画像にしない。失敗時は`場所・原因（不明なら不明）・対処`とexit codeを出す。

## 対象外

汎用動画codec、音声同期、raw-playerの全API互換、120fps達成の先行宣言は行わない。

## 根拠

- [全example](https://github.com/shiguredo/raden/tree/afb752e17a69fef8af981251b68de22a7597ff01/examples)
- [basic_drawing](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs)
- [animation](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/animation.rs)
- [raden_player](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/raden_player.rs)
- [tigerデータの出典コメント](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/tiger/tiger_data.rs)

検証状態: 未実行（実装計画）。
