///|
/// SHA-256 (FIPS PUB 180-4) の実装。
///
/// conformance 成果物の input/output hash 計算専用。
/// メッセージ全体をメモリ上に保持する入力を前提とした one-shot 実装。
/// 暗号学的用途 (HMAC 等) ではなく、成果物の完全性照合だけに用いる。

///|
/// ラウンド定数 K (FIPS 180-4 §4.2.2)。
let k256 : FixedArray[UInt32] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
  0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
  0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
  0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
  0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
  0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
  0xc67178f2,
]

///|
/// 初期ハッシュ値 H(0) (FIPS 180-4 §5.3.3)。
let h0 : FixedArray[UInt32] = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
  0x5be0cd19,
]

///|
/// 右ローテート。
fn rotr(x : UInt32, n : Int32) -> UInt32 {
  (x >> n) | (x << (32 - n))
}

///|
/// 64 バイトブロック 1 個分の圧縮関数。
fn compress(h : FixedArray[UInt32], block : BytesView, off : Int32) -> Unit {
  // メッセージスケジュール W[0..63]
  let w = FixedArray::make(64, 0U)
  for i in 0..<16 {
    let p = off + i * 4
    w[i] = (block[p].to_uint() << 24) |
      (block[p + 1].to_uint() << 16) |
      (block[p + 2].to_uint() << 8) |
      block[p + 3].to_uint()
  }
  for i in 16..<64 {
    let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
    let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
    w[i] = w[i - 16] + s0 + w[i - 7] + s1
  }
  let mut a = h[0]
  let mut b = h[1]
  let mut c = h[2]
  let mut d = h[3]
  let mut e = h[4]
  let mut f = h[5]
  let mut g = h[6]
  let mut hh = h[7]
  for i in 0..<64 {
    let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
    let ch = (e & f) ^ ((e ^ 0xFFFFFFFF) & g)
    let t1 = hh + s1 + ch + k256[i] + w[i]
    let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
    let maj = (a & b) ^ (a & c) ^ (b & c)
    let t2 = s0 + maj
    hh = g
    g = f
    f = e
    e = d + t1
    d = c
    c = b
    b = a
    a = t1 + t2
  }
  h[0] = h[0] + a
  h[1] = h[1] + b
  h[2] = h[2] + c
  h[3] = h[3] + d
  h[4] = h[4] + e
  h[5] = h[5] + f
  h[6] = h[6] + g
  h[7] = h[7] + hh
}

///|
/// 入力バイト列の SHA-256 ダイジェスト (32 バイト) を返す。
pub fn sha256(data : BytesView) -> Bytes {
  let h = FixedArray::make(8, 0U)
  for i in 0..<8 {
    h[i] = h0[i]
  }
  // パディング: 末尾を 0x80 + 0x00* + ビット長 (BE 8B) で 64 の倍数にする。
  let len = data.length()
  let bit_len : UInt64 = len.to_uint64() * 8
  let padded_len = (len + 9 + 63) / 64 * 64
  let padded = FixedArray::make(padded_len, b'\x00')
  padded.blit_from_bytesview(0, data)
  padded[len] = b'\x80'
  for i in 0..<8 {
    padded[padded_len - 1 - i] = (bit_len >> (i * 8)).to_byte()
  }
  let padded_view : BytesView = Bytes::from_array(padded[:])[:]
  let mut off = 0
  while off < padded_len {
    compress(h, padded_view, off)
    off = off + 64
  }
  // H を BE バイト列へ出力する。
  let out = FixedArray::make(32, b'\x00')
  for i in 0..<8 {
    out.unsafe_write_uint32_be(i * 4, h[i])
  }
  Bytes::from_array(out[:])
}

///|
/// 入力バイト列の SHA-256 を小文字 hex 文字列で返す。
/// meta.json の `input_sha256` / `output_sha256` にそのまま埋め込む形式。
pub fn sha256_hex(data : BytesView) -> String {
  let digest = sha256(data)
  let sb = StringBuilder()
  for b in digest {
    let v = b.to_uint()
    let hi = (v >> 4) & 0xF
    let lo = v & 0xF
    sb.write_char(hex_digit(hi))
    sb.write_char(hex_digit(lo))
  }
  sb.to_string()
}

///|
/// 0..15 を '0'-'f' へ変換する。
fn hex_digit(v : UInt32) -> Char {
  if v < 10 {
    Int32::unsafe_to_char('0'.to_int() + v.reinterpret_as_int())
  } else {
    Int32::unsafe_to_char('a'.to_int() + v.reinterpret_as_int() - 10)
  }
}
