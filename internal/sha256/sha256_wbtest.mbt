///|
/// SHA-256 の既知ベクトル検証 (FIPS 180-4 / NIST テスト値)。
test "sha256 既知ベクトル" {
  // 空入力のダイジェストは規格で固定。
  inspect(
    sha256_hex(b""),
    content="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  // "abc" のダイジェストも規格値。55 バイトで 1 ブロック境界の動作を確認する。
  let abc : Bytes = b"abc"
  inspect(
    sha256_hex(abc[:]),
    content="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  // 56 バイト以上でパディングが 2 ブロックに跨るケース。
  let long : Bytes = b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  inspect(
    sha256_hex(long[:]),
    content="248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
}

///|
/// 64 バイトちょうど (ブロック境界) の入力でも正しく圧縮されることを確認する。
test "sha256 ブロック境界" {
  let data = FixedArray::make(64, b'a')
  let bytes = Bytes::from_array(data[:])
  inspect(
    sha256_hex(bytes[:]),
    content="ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
  )
}
