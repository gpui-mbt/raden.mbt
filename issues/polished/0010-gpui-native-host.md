# gpui.mbtを表示ホストとして使うNativeデモ

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0010-gpui-native-host

Issue: RADEN-0010
Priority: P2
Milestone: M4
Depends-on: RADEN-0008

## 概要

raden.mbtのCPU描画結果をgpui.mbtのウィンドウへ表示し、同じsceneをブラウザとNativeで使えることを実証する。gpui.mbtのrendererを全面置換するのではなく、画像表示を介した小さな統合にする。

## 背景

- gpui.mbtの公開APIと利用可能versionは着手時に確認・固定する。raw pixel/画像upload、image element相当の表示、resize/DPI、pointer/keyboard event、再描画要求、window閉鎖が必要機能。
- 初期対応targetはNative（Linuxを自動化先行、macOS Apple Siliconを実機検証）で、Mac Intelは対象外（[issues/README.md](../README.md) の設計判断4）。
- 本Issueは RADEN-0010（依存: RADEN-0008）。CPU描画コアにGPU/ブラウザ依存を入れず、ホスト層へ分離する。

## 問題

- Nativeウィンドウ表示の統合が存在せず、同一sceneのブラウザ/Native比較ができない。
- gpui.mbtの必要APIの可用性が未確認で、画像受け渡しとbuffer寿命の契約が未定義。
- GUI環境のないCIでcore検証を継続する構成が未確立。

## 目標

- 固定依存のgpui.mbtを使う独立Native consumerで、basic_drawingのraw bufferを表示できる。
- core-only consumerにgpui/Node依存が入らず、GUIなしCIでもheadless検証が動く。
- Linux/macOS別に起動・操作・表示結果を実行環境ごとに報告できる。

## 対象外

- gpui rendererの全面置換、OS window実装の新規移植、raw-player/SDL全体、未検証のWindows/Mac Intel対応、最初からのzero-copy。

## 提案する方針

1. 着手時のgpui.mbt公開APIと利用可能versionを確認・固定する。必要な機能はraw pixel/画像upload、image elementまたは同等の表示、resize/DPI、pointer/keyboard event、再描画要求、window閉鎖である。既存API名や完成状態を推測してadapterを書かない。
2. 画像受け渡しAPIが不足していたら、最小再現consumerと必要な契約をgpui側の別Issue/PRへ切り出す。raden側のheadless/browser開発は止めない。Rust GPUIや上流radenのFFI呼出しへ無断で置き換えない。
3. `examples/native_gpui/` 等をcoreと別module/consumerにする。core利用者がgpui、platform SDK、Nodeを導入せずに済むdependency graphを保つ。公開済み依存を使うか固定commitを使うかをmanifestで明示する。
4. 初期はraw bufferのcopy/uploadを採用し、所有者、stride、byte order、alpha表現、upload終了のタイミングを文書化する。再確保や描画中のbufferをGPU/hostが読むraceを防ぐ。ゼロコピーは測定後の別課題とする。
5. CPU描画、pixel変換/copy、upload、表示を分離して計測する。radenのCPU rasterに対し、gpuiの表示がGPUを使うことは別層として説明する。GUIが使えないCIでもheadless core検証を実行できるようにする。
6. 最初はbasic_drawingとreset/resize/close。次にbrowserと同じscene parameter modelを使用してpreset、制御点、frame停止/送りを追加する。表示size/DPR/scene座標を分け、resizeで意図せずfixture入力を変えない。
7. Linuxを自動化先行、macOS Apple Siliconを実機検証対象とする。Mac Intelは対象外。OS別のpermission、display server、GPU環境がない場合はblocked_environmentを記録し、headless成功からGUI成功を推定しない。
8. GUI検証にvlmkitを使う際は、選択したwindowへの入力束縛を確認する。windowが閉じた、隠れた、別windowが前面に来た場合に意図しない入力を送らない。自動化で確認できない項目は手動記録と区別する。

### 成果物

- gpui.mbtの固定依存を使用する独立Native consumer。
- raw buffer upload/寿命のadapter契約と最小画像表示テスト。
- Linux/macOS別の起動手順、実機確認記録、未確認項目。
- Web/Nativeで同じfixture id/入力を使うデモと、表示処理時間の内訳。

## 受け入れ条件

- [ ] Given 同一scene, when headless実行とgpui表示を比較する, then coreのraw hashが一致し、半透明と不透明の色パッチでupload前後のalpha/byte order誤りが検出される。
- [ ] Given window起動、reset、resize、DPR変更、複数回の開閉、終了, when 実行する, then 古いbuffer参照、double free、残ったtimer/workerがない。
- [ ] Given 非正方画像、paddingを持つstride、半透明背景、scale変更, when 表示する, then 表示の反転/歪み/色ずれが検証され、スクリーンショットがhost表示検証として保存される。
- [ ] Given pointer操作, when 対象windowとscene座標を確認する, then 背面/閉鎖/他windowへの入力を防止するテストが通る。
- [ ] LinuxとmacOSが別々にPASS/FAIL/未実行として報告される。windowが開いたことだけで全操作・表示比較成功としない。
- [ ] Given core-only consumer, when 依存を検査する, then gpui/Nodeが入らず、GUI依存を除いた環境で従来のheadlessテストが動く。
- [x] gpui.mbtの必要APIの可用性確認結果が記録され、不足時の切り出し先が明記されている。

## テスト計画

- basic_drawingをheadlessで実行し、gpui表示とのraw hash比較を実行する。
- windowライフサイクル（起動、reset、resize、DPR変更、開閉、終了）の手動/自動テストを実行する。
- 色パッチと非正方/stride付き画像の表示テストを実行する。
- 入力束縛テスト（window閉鎖、背面、他window）を実行する。
- LinuxとmacOSで別々に実行し、結果を分けて記録する。

## リスク

- gpui.mbtの必要APIが未提供の可能性がある。確認を先行し、不足時はgpui側へ切り出してraden側を止めない。
- buffer寿命とGPU uploadのraceで不定な表示不具合が出る。copy/upload契約とタイミングを文書化する。
- GUI環境のないCIではGUI検証を実行できない。headless成功をGUI成功へ読み替えない。
- vlmkitの入力が意図しないwindowへ届く危険がある。選択と前面状態を確認する。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [上流の描画/表示分離例](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs)
- [gpui.mbt（着手時にAPI/versionを確認する接続先）](https://github.com/gpui-mbt/gpui.mbt)
- [MoonBit FFIの型・寿命](https://docs.moonbitlang.com/en/stable/language/ffi.html)

## 注記

- 検証状態: **blocked (gpui 側 API 不足)**。2026-10-17 に f4ah6o/gpui@0.7.2
  (mooncakes 最新公開版) の全 `pkg.generated.mbti` を走査して確認した。
- API 可用性調査結果:

  | 必要機能 | 有無 | 根拠 |
  | --- | --- | --- |
  | window 開閉 | 有 | `ubuntu::Host::create_window/destroy_window/request_close` |
  | pointer/keyboard event | 有 | `Host::dispatch/next_event` → `@platform.Event` |
  | resize/DPR | 有 | `set_size` / `window_metrics` / `frame_metrics` |
  | 再描画要求 | 一部 | `present(WindowId, SceneSnapshot)` Scene 経路のみ |
  | raw pixel/画像 upload | **無** | `SceneItem`=Quad/Text/TextRun、`PaintKind`=Quad/ClipPush/ClipPop のみ |
  | 画像 element | **無** | element/scene の公開面に画像項目なし |

  `Host::copy_frame` は `@testing.FrameReadback` の読み戻し専用で upload ではない。
- 切り出し先: `issues/open/20261017-gpui-image-display-item.md` に
  要求契約 (premultiplied RGBA8 + stride + copy 契約 + FrameReadback 検証) を
  記録。gpui-mbt/gpui.mbt 側での提供を待つ。
- moon.mod へ一時追加した f4ah6o/gpui 依存は除去済み (adapter を書けないため
  core 消費者に不要な依存を残さない)。
- 本Issueは [issues/README.md](../README.md) のM4（Native統合・テキスト）に含まれ、RADEN-0011とは別々に判定する。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
