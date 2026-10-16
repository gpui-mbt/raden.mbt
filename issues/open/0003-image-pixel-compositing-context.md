---
id: RADEN-0003
status: open
priority: P1
milestone: M1
depends_on: [RADEN-0001]
---

# Image・ピクセル合成・Contextで最初の画像を描く

## 目的

`basic_drawing`をMoonBitだけで描ける最小コアを作る。曲線、JIT、ウィンドウ、フォントを必要としない縦切りで、NativeとJSの両方から同じピクセルを得る。

## 実装方針

1. `Image`にwidth/height/stride/formatと所有bufferを持たせる。初期formatはPrgb32。packed pixelは論理ARGB、外部byte orderは明示的に固定し、ホストのendian任せで変換しない。上流basic_drawingのLE BGRAをcanonical形式へ変換する規則をRADEN-0002と共有する。
2. `width * bytes_per_pixel`、`stride * height`はoverflowと上限を確保前に検証する。0寸法の扱い、padding付きstride、buffer length不一致を仕様化する。初期constructorが連続bufferのみを許す場合でも、将来host adapterが勝手に同じ前提へ依存しないようstrideをAPIに残す。
3. `Rgba32`入力、premultiply、unpremultiplyの役割を分ける。描画内部はpremultipliedで統一し、unpremultiplyは表示/exportの必要な場所だけで行う。alpha=0のRGB、rounding、clamp、符号付きshift、packed UInt操作を明示する。
4. `SrcCopy`、`SrcOver`、`Clear`、`Plus`のスカラ演算を小さな関数で実装する。上流JITの`(x * 257 + 257) >> 16`等の整数処理と実際のsourceを確認し、一般的な浮動小数点の合成式へ置き換えない。完全coverageと部分coverageの経路を分けてテストする。
5. `Context`にfill/stroke styleの土台、comp op、global/fill/stroke alpha、matrix、rect clip、save stackを持たせる。初期styleは単色。save/restoreは値として状態を保持し、後からstyle/clipを変更して保存状態まで変わらないようにする。stack空のrestoreの挙動は上流観測と安全方針を記録する。
6. `fill_all`、identity変換の`fill_rect`、`clear_all`、`clear_rect`、`clip_to_rect`、`restore_clipping`を実装する。clipは画像境界との積集合を維持する。clearはfill style/comp opに依存しない操作として調べ、`clear_rect`の座標系を通常fillと混同しない。
7. M1では整数座標の矩形を完全対応とし、小数矩形の端点処理も上流で調べて対応表へ分ける。未実装の非identity変換や未知formatを無言のno-opにしない。RADEN-0005でpath fallbackを接続するまでは明示的な未対応結果にする。
8. Xrgb32/A8は次のsub-PRで追加する。上流固定READMEのA8対応範囲は限定的であるため、Prgb32に名前だけ付け替えない。format×operationの対応表とテストを作り、alphaの意味とX channelの出力を観測する。

## 成果物

- 公開Image/Rgba32/Context API、スカラ合成、bounds/clip/state実装。
- 純粋な`basic_drawing` scene。1280×720、背景と3矩形の値・順序を上流と一致させる。
- raw buffer出力APIとNative/JS consumer。ファイルI/Oはここへ入れずRADEN-0008のhostへ渡す。
- API対応表に「Prgb32整数矩形」「小数矩形」「Xrgb32」「A8」を別行で記載する。

## テストと受入条件

1. alpha/coverageの0、1、127、128、254、255と端点、完全透明、完全不透明、半透明の連続重ね描きで上流と比較する。整数合成の完全一致をM1のゲートにする。
2. 矩形が全外、各辺を横断、負座標、0サイズ、1画素、clip空、clip復元、save/restore入れ子を検証する。画像外のguard領域が変わらないことも確認する。
3. 幅1/2/3/4/5/7/8/9でtailと端処理を確認し、Native/JSで同じraw bytesになること。
4. 過大dimension、不正stride、非有限alpha/座標、上限超過で予測可能なエラーとなり、途中の画像破壊や過大確保を防ぐ。
5. RADEN-0002に接続し、`basic_drawing`全画素の一致と、色/alpha/clipの負の対照の検出を実証する。単体テストだけではM1完了としない。

## 対象外

29モード全部はRADEN-0007、pathと変換の実描画はRADEN-0004/0005、BMPとウィンドウ表示はRADEN-0008以降。未対応formatのfallbackを使って成功扱いしない。

## 根拠

- [Image](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/api/image.rs)
- [basic_drawingの寸法・色・byte order](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs)
- [整数合成](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)
- [固定版の対応範囲](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/README.md)

検証状態: 未実行（実装計画）。
