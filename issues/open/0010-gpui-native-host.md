---
id: RADEN-0010
status: open
priority: P2
milestone: M4
depends_on: [RADEN-0008]
---

# gpui.mbtを表示ホストとして使うNativeデモ

## 目的

raden.mbtのCPU描画結果をgpui.mbtのウィンドウへ表示し、同じsceneをブラウザとNativeで使えることを実証する。gpui.mbtのrendererを全面置換するのではなく、画像表示を介した小さな統合にする。

## 実装方針

1. 着手時のgpui.mbt公開APIと利用可能versionを確認・固定する。必要な機能はraw pixel/画像upload、image elementまたは同等の表示、resize/DPI、pointer/keyboard event、再描画要求、window閉鎖である。既存API名や完成状態を推測してadapterを書かない。
2. 画像受け渡しAPIが不足していたら、最小再現consumerと必要な契約をgpui側の別Issue/PRへ切り出す。raden側のheadless/browser開発は止めない。Rust GPUIや上流radenのFFI呼出しへ無断で置き換えない。
3. `examples/native_gpui/`等をcoreと別module/consumerにする。core利用者がgpui、platform SDK、Nodeを導入せずに済むdependency graphを保つ。公開済み依存を使うか固定commitを使うかをmanifestで明示する。
4. 初期はraw bufferのcopy/uploadを採用し、所有者、stride、byte order、alpha表現、upload終了のタイミングを文書化する。再確保や描画中のbufferをGPU/hostが読むraceを防ぐ。ゼロコピーは測定後の別課題とする。
5. CPU描画、pixel変換/copy、upload、表示を分離して計測する。radenのCPU rasterに対し、gpuiの表示がGPUを使うことは別層として説明する。GUIが使えないCIでもheadless core検証を実行できるようにする。
6. 最初はbasic_drawingとreset/resize/close。次にbrowserと同じscene parameter modelを使用してpreset、制御点、frame停止/送りを追加する。表示size/DPR/scene座標を分け、resizeで意図せずfixture入力を変えない。
7. Linuxを自動化先行、macOS Apple Siliconを実機検証対象とする。Mac Intelは対象外。OS別のpermission、display server、GPU環境がない場合はblocked_environmentを記録し、headless成功からGUI成功を推定しない。
8. GUI検証にvlmkitを使う際は、選択したwindowへの入力束縛を確認する。windowが閉じた、隠れた、別windowが前面に来た場合に意図しない入力を送らない。自動化で確認できない項目は手動記録と区別する。

## 成果物

- gpui.mbtの固定依存を使用する独立Native consumer。
- raw buffer upload/寿命のadapter契約と最小画像表示テスト。
- Linux/macOS別の起動手順、実機確認記録、未確認項目。
- Web/Nativeで同じfixture id/入力を使うデモと、表示処理時間の内訳。

## テストと受入条件

1. coreのraw hashはheadless実行と一致すること。gpui upload前後のalpha/byte order誤りを、半透明と不透明の色パッチで検出する。
2. window起動、reset、resize、DPR変更、複数回の開閉、終了を実際に実行し、古いbuffer参照、double free、残ったtimer/workerがないことを確認する。
3. 非正方画像、paddingを持つstride、半透明背景、scale変更で表示の反転/歪み/色ずれを検証する。スクリーンショットはhost表示検証として保存する。
4. pointerの操作対象とscene座標を確認し、背面/閉鎖/他windowへの入力を防止するテストを行う。
5. LinuxとmacOSは別々にPASS/FAIL/未実行を報告する。windowが開いたことだけで全操作・表示比較成功としない。
6. core-only consumerの依存にgpui/Nodeが入らないことを検査する。GUI依存を除いた環境で従来のheadlessテストが引き続き動くこと。

## 対象外

gpui rendererの全面置換、OS window実装の新規移植、raw-player/SDL全体、未検証のWindows/Mac Intel対応、最初からのzero-copyは含めない。

## 根拠と接続時の確認先

- [上流の描画/表示分離例](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs)
- [gpui.mbt（着手時にAPI/versionを確認する接続先）](https://github.com/gpui-mbt/gpui.mbt)
- [MoonBit FFIの型・寿命](https://docs.moonbitlang.com/en/stable/language/ffi.html)

検証状態: 未実行（実装計画）。gpui側の必要APIの可用性も着手時確認事項。
