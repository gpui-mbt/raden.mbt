# gpui.mbtへの画像シーン項目 (ImageItem) 要求

Status: open
Model: unknown
Created: 2026-10-17
Branch: feat/gpui-image-display-item

Issue: (採番なし。gpui-mbt/gpui.mbt 側への切り出し要求を管理するローカル記録)
Priority: P2
Depends-on: RADEN-0010 の API 可用性調査結果

## 概要

raden.mbt の RADEN-0010 (gpui native host) 実施に必要な、raw ピクセルバッファをウィンドウへ表示する API が f4ah6o/gpui@0.7.2 に存在しない。gpui.mbt 側へ ImageItem 相当のシーン項目を要求し、提供まで RADEN-0010 は blocked とする。

## 背景

- 確認対象: mooncakes 公開の `f4ah6o/gpui@0.7.2` (2026-10-17 時点の最新公開版、`moon search gpui` で確認)。
- 調査方法: モジュールを vendoring し全 `pkg.generated.mbti` を走査。`image|texture|bitmap|canvas|sprite|surface|pixels` のいずれの命名でも表示用項目は見つからなかった。
- 上流の描画/表示分離例: https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs

## 問題

`SceneItem` のバリアントは `QuadItem` / `TextItem` / `TextRunItem` のみ、`PaintKind` は `Quad` / `ClipPush` / `ClipPop` のみで、外部から生成したピクセルバッファを表示する経路が公開 API に存在しない。

- `Host::copy_frame(WindowId, FixedArray[Byte])` は `@testing.FrameReadback` の読み戻し API であり、表示への upload ではない。
- `Host::present(WindowId, SceneSnapshot)` は Scene グラフ経路のみ。
- quad のグリッドで画素を模倣する回避策は性能・契約上成立しない。

## 目標

gpui.mbt が以下のいずれかを提供し、raden.mbt 側で headless 生成した canonical premultiplied RGBA8 をウィンドウ表示できること。

- 優先: `SceneItem` への画像バリアント (例: `ImageItem`) または同等の scene item
- 代替: `Host::present` と同等のライフサイクルを持つ直接 framebuffer upload

## 対象外

- gpui renderer 内部実装の提案 (GPU/ソフトウェアどちらでもよい)
- ゼロコピー最適化。初期は copy/upload でよい
- Rust 版 GPUI や上流 raden の FFI 経由表示への置き換え

## 提案する方針

要求する最小契約を以下に固定する。これを gpui-mbt/gpui.mbt 側の Issue/PR として送る。

1. 入力形式: premultiplied RGBA8 (`R,G,B,A` 順のバイト列)。幅・高さ・stride を明示する。stride バイト単位、padding 許容。
2. 所有権: upload 呼び出し完了時点でバッファの内容が確定していること (呼び出し側は呼び出し後にバッファを再利用・破棄してよい = コピー契約)。
3. 配置: bounds rect + 拡縮なし (1:1) が最小。拡縮フィルタは任意。
4. 失敗: 未対応フォーマット・サイズ超過は `Result` のエラーで返すこと。
5. 検証: `FrameReadback` で表示後のピクセルを読み戻せること。色パッチ (不透明赤、半透明緑、alpha=0) の upload→readback 往復で byte order/alpha 誤りを検出可能なこと。

## 受け入れ条件

- [ ] gpui.mbt 側に画像表示 API の Issue/PR が作成され、リンクが本 Issue に記録されている。
- [ ] 提供バージョンで `examples/native_gpui` consumer が basic_drawing (1280x720) をウィンドウ表示できる。
- [ ] 半透明・不透明の色パッチで upload→FrameReadback の往復が画素一致する。

## テスト計画

- gpui 側提供後に RADEN-0010 の受け入れ条件へ接続する。
- 最小再現: 1 ウィンドウ・1 画像・不透明色パッチの表示を smoke 化する。

## リスク

- gpui 側の仕様 (alpha 表現・byte order・stride 規約) が raden の canonical 形式と異なる場合、adapter での変換コストが増える。契約を先行して文書化し齟齬を防ぐ。

## 変更履歴

`CHANGES.md` impact: no

## 注記

- 本 Issue は gpui-mbt/gpui.mbt リポジトリ側への要求を raden.mbt ローカルで管理するためのもの。対応版が出るまで RADEN-0010 は実装不可。
- 回避案として platform.Backend 実装側を自作する案もあるが、それは gpui ウィンドウ表示ではなく別 host の自作になるため本 Issue の対象外。
