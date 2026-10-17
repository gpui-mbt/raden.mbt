# 上流example全8本を追跡し、共通sceneとヘッドレスCLIを作る

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0008-examples-headless

Issue: RADEN-0008
Priority: P1
Milestone: M1-M4
Depends-on: RADEN-0002, RADEN-0003

## 概要

ライブラリの移植率だけでなく、利用者が実行できるexampleで完成範囲を示す。描画sceneと表示/ファイル/時計のhostを分け、同じsceneをNative CLI、Web、gpuiへ渡す。

## 背景

- 上流examplesは8本（basic_drawing、gradient_drawing、stroke_drawing、blit_clip_pattern_paths、animation、tiger、raden_player、font_shaping）。それぞれが参照するcore機能は本リポジトリのRADEN-0003〜0011に対応する。
- デモのスクリーンショットは表示ホスト検証、生ピクセル比較は描画コア検証として分離する（[issues/README.md](../README.md) の共通合格基準）。
- 本Issueは RADEN-0008（依存: RADEN-0002、RADEN-0003）。M1は `basic_drawing` だけで成立させる。

## 問題

- 現状はsceneを実行する手段がなく、実装済み範囲を利用者へ示せない。
- 壁時計、乱数、ファイルパスに依存するscene設計だと、goldenが時刻や環境で揺れる。
- 未実装exampleを空画像や成功exitで返すと、対応範囲を誤認させる。

## 目標

- 8本すべてがmanifestで状態追跡され、実行可能なexampleはNative/JSのヘッドレスで同じsceneを出力できる。
- `raden-demo` 相当のCLIでexample、size、fps、frame、seedを指定し、raw pixelとmetadataを成果物にできる。
- 未対応・未実行を成功扱いせず、失敗時は場所・原因・対処とexit codeを出す。

## 対象外

- 汎用動画codec、音声同期、raw-player全API互換、120fps達成の先行宣言。
- ウィンドウ表示そのもの（RADEN-0009/0010）。

## 提案する方針

1. 上流exampleの描画関数・定数・描画順を調べてfixture化する。同名だけの別デモを作らず、意図的に変えたUIと変更していないsceneを区別する。デモの初期値とテスト用値が分岐しないよう同じscene builderを使う。
2. 共通sceneは入力parameterとframe indexを受け、MoonBitの描画APIを呼ぶ。壁時計、乱数、ウィンドウイベント、ファイルパスを直接読まない。乱数を使う上流sceneは実際の生成方法を調べ、seedまたは生成済み入力を共有する。
3. Native CLIを作る。提案interfaceは `raden-demo --example basic_drawing --headless --output <dir>`、animationは `--width / --height / --fps / --frame / --seed` を追加する。これは未実装の案であり、実装後に正確な起動commandと出力先をREADMEへ掲載する。
4. 生ピクセルとmetadataを標準成果物にする。BMP writerは独立したcodec/host層としてtop-down、チャンネルmask、stride、alpha扱いを検証する。ブラウザは同じbytesを表示し、ファイルI/Oをcoreへ持ち込まない。
5. animationはテスト時に `time = frame_index / fps` で決定する。real-time実行は同じsceneにホスト時刻から得たframeを渡す。停止、1frame送り、再開、最初へ戻る、サイズ変更を明示的な操作にする。
6. 上流animationの `--duration` によるベンチ方式を調べ、時間制限runと固定frame数runを分ける。性能測定では同じscene/size/frame範囲、compile modeを使い、表示待ち時間と描画時間を分離する。
7. `raw_player` は上流の表示ホストであり、本IssueでMoonBitへ全移植しない。ウィンドウ表示はRADEN-0009/0010で別途提供する。`raden_player` のscene部分だけ完成してもVideoPlayer互換完成と表示しない。
8. tigerは出典台帳と再配布条件を確認した後にデータを変換する。変換script、source hash、command/point数を保存し、変換済みのデータだけを手修正しない。未確認の時は独自の複雑path fixtureでcoreを進め、tigerはblockedのまま残す。

### example対応計画

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

この表は移植予定であって実装済み一覧ではない。`examples/manifest.json` に各exampleの `core / native_headless / browser / gpui / pixel_parity` を別statusとして持たせる。

### 成果物

- `examples/manifest.json`、共通scene、headless CLI、BMP/raw出力。
- 各exampleのREADME、起動command、依存、対応target、スクリーンショットと比較状況。
- basic→曲線→stroke/paint→複雑scene→fontという小刻みな実装PR。

## 受け入れ条件

- [ ] Given M1の範囲, when `basic_drawing` をNative/JSで実行する, then raw比較とBMP decode後のchannel/寸法が検証される。
- [ ] 全8本がmanifestに登録され、未実装が欠落していない。新しいexampleを取り込む時は固定SHAと表が明示更新される。
- [ ] Given seed/frame/sizeが同じrun, when 実行する, then 同じhashになり、異なる入力が同じrequestとして再利用されない。fps=0、巨大frame/size、未知example、出力不能は明示エラーになる。
- [ ] Given animation停止中, when 観測する, then frame/hashが変わらず、1frame送りで期待した入力だけが変化する。wall clockに依存したgoldenを保存しない。
- [ ] Given 独立consumer, when 各完成exampleを実行する, then library APIだけで動作する。内部関数に直接依存するテストだけで配布可能としない。
- [ ] 未対応のexampleが成功exitの空画像にならず、失敗時は「場所・原因（不明なら不明）・対処」とexit codeを出す。

## テスト計画

- `basic_drawing` をNative/JSで実行し、raw pixelとBMP decode結果をRADEN-0002で比較する。
- `examples/manifest.json` の全8本の状態を照合する。
- seed/frame/sizeごとのhash再現テストと異常入力（fps=0、巨大値、未知example）テストを実行する。
- animationの停止/送り/再開/リセット操作テストを実行する。
- 独立consumerから各完成exampleを実行する。
- 実行コマンドは実装後にREADMEへ記載する。

## リスク

- 上流sceneをUI都合で変更すると、固定画像比較の意味が失われる。変更していないsceneと意図的な変更を区別して記録する。
- wall clock・乱数に依存するgoldenは不安定になる。frame index/seedで決定する。
- tigerの出典・再配布条件が確認できない限り配布できない。独自fixtureでcoreを先行させる。
- `raden_player` のscene移植をVideoPlayer互換と誤認させる危険がある。表示ホストは別Issueとして明示する。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [全example](https://github.com/shiguredo/raden/tree/afb752e17a69fef8af981251b68de22a7597ff01/examples)
- [basic_drawing](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs)
- [animation](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/animation.rs)
- [raden_player](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/raden_player.rs)
- [tigerデータの出典コメント](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/tiger/tiger_data.rs)

## 注記

- 検証状態: 完了 (2026-10-17 実施)。ready 6 本
  (basic/gradient/stroke/blit_clip_pattern/animation/font_shaping) を
  `examples/run_examples.sh` で oracle raw hash + BMP decode 一致まで検証。
  blocked 2 本 (tiger: provenance 未確認、raden_player: raw_player host と
  1920x1080 scene 移植が必要) は非 0 exit を確認。`examples/raden-demo/bmp.mbt`
  が上流 `src/codec/bmp.rs` と同じ top-down 32bpp BI_BITFIELDS を出力し、
  meta に bmp hash を記録する。manifest は core/native_headless/browser/gpui/
  pixel_parity を個別 status で持つ。
- 本Issueは [issues/README.md](../README.md) のM1〜M4にまたがる。M1（最初のデモ）の中核で、basic以外は後続Issueと同時に段階追加する。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
