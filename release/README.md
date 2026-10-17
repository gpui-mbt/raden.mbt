# preview 配布手順 (未実行)

`release/manifest.json` が宣言した範囲の preview 配布手順。
publish/deploy は明示的な実行判断を経るため、本ファイルは手順と
検証までを記述する (実 publish は行っていない)。

## 手順

1. `scripts/run_checks.sh --with-bench` が全緑であること。
   required job の missing/fail/cancelled/skip は gate を通さない。
2. `release/inspect_artifact.sh` で artifact 検査
   (絶対パス・秘密情報・開発生成物の混入なし、runtime 依存が宣言内)。
3. `scripts/run_consumer_test.sh` で独立 consumer 導入を確認
   (native / js 両方で basic drawing を実行)。
4. mooncakes 公開 (未実行):
   `moon publish` — パッケージ名 `gpui-mbt/raden`、version は
   `moon.mod` と manifest の一致を確認してから行う。
5. GitHub Release (未実行): conformance/bench の report と
   manifest の対応表を添付する。

## 依存・asset 台帳

- runtime 依存: `moonbitlang/async@0.22.4` (fs/時刻のみ。pure core 未使用)
- `conformance/fonts/SourceSans3-Regular.ttf`: SIL OFL 1.1、
  sha256 は `upstream.lock.json` / fonts/README.md に記録。
  検証用途で同梱、runtime への埋め込みなし。
- tiger asset: 出典・再配布条件未確認のため artifact 対象外 (blocked)。
