///|
/// パックドピクセル演算のスカラ実装。
///
/// 上流 (Rust/Cranelift JIT) は 32bit ワード単位で合成を行う。
/// 本パッケージは同じ演算を `UInt` のプリミティブで再現する。
/// ワードのレイアウトは `0xAARRGGBB` (premultiplied) とする。
///
/// 上流の JIT が生成する整数演算をそのまま移植し、
/// 浮動小数点ブレンド式や `d * (255 - a) / 255` のような
/// 結果の異なる一般式には置き換えない。

///|
/// 0..=1 のアルファ値を 0..=255 の整数に丸める。範囲外・非有限値はクランプする。
/// 上流 `context.rs` の `alpha_to_u8` に対応。
pub fn alpha_to_u8(a : Double) -> UInt32 {
  if a.is_nan() || a.is_inf() || a <= 0.0 {
    0
  } else if a >= 1.0 {
    255
  } else {
    // 上流は (a * 255.0 + 0.5) as u8 (切り捨て)。a < 1 なら 255 を超えない。
    (a * 255.0 + 0.5).to_int().reinterpret_as_uint()
  }
}

///|
/// 8bit 整数 RGBA を premultiplied ARGB32 (0xAARRGGBB) に変換する。
/// 上流 `pixel/mod.rs` の `premultiply_rgba` に対応。
/// 各チャネルは `(c * a + 128) / 255` で丸める (整数除算)。
pub fn premultiply_rgba(
  r : UInt32,
  g : UInt32,
  b : UInt32,
  a : UInt32,
) -> UInt32 {
  let a8 = a & 0xFF
  (a8 << 24) |
  ((((r & 0xFF) * a8 + 128) / 255) << 16) |
  ((((g & 0xFF) * a8 + 128) / 255) << 8) |
  (((b & 0xFF) * a8 + 128) / 255)
}

///|
/// premultiplied ARGB32 ピクセルを 0..=255 のアルファでスケールする。
/// 上流 `context.rs` の `scale_prgb32` に対応。
/// 全チャネルを等しく乗算するため premultiplied 不変条件は保たれる。
/// 除算は `(v + 0x80 + (v >> 8)) >> 8` の近似式 (最大 1 LSB の誤差)。
pub fn scale_prgb32(prgb32 : UInt32, alpha : UInt32) -> UInt32 {
  if alpha == 0xFF {
    return prgb32
  }
  if alpha == 0 {
    return 0
  }
  let a = alpha & 0xFF
  let sc = fn(c : UInt32) -> UInt32 {
    let v = c * a + 0x80
    (v + (v >> 8)) >> 8
  }
  (sc((prgb32 >> 24) & 0xFF) << 24) |
  (sc((prgb32 >> 16) & 0xFF) << 16) |
  (sc((prgb32 >> 8) & 0xFF) << 8) |
  sc(prgb32 & 0xFF)
}

///|
/// Blend2D 方式の div255。`(x * 257 + 257) >> 16`。
/// 上流 JIT の coverage スケールに使われる近似除算で、
/// x <= 255*255 = 65025 の範囲で正確。
fn div255_prod(prod : UInt32) -> UInt32 {
  (prod * 257 + 257) >> 16
}

///|
/// src の各チャネルにカバレッジを乗算する。
/// 上流 JIT の `cov_src_c = div255(src_c * cov)` に対応。
/// cov=0xFF なら src をそのまま返す (div255(c * 255) = c)。
fn apply_coverage(src : UInt32, cov : UInt32) -> UInt32 {
  if cov == 0xFF {
    return src
  }
  let c = cov & 0xFF
  (div255_prod(((src >> 24) & 0xFF) * c) << 24) |
  (div255_prod(((src >> 16) & 0xFF) * c) << 16) |
  (div255_prod(((src >> 8) & 0xFF) * c) << 8) |
  div255_prod((src & 0xFF) * c)
}

// ---------------------------------------------------------------------------
// Porter-Duff 合成演算 (dst, src) -> out
// ---------------------------------------------------------------------------

///|
/// SrcCopy: 単純に src を書き込む。
pub fn comp_src_copy(dst : UInt32, src : UInt32) -> UInt32 {
  let _ = dst
  src
}

///|
/// SrcCopy + coverage。
/// 上流 `build_src_copy_cov` と同じく dst を読まず
/// `div255(src_c * cov)` を直接書き込む (cov=0 なら 0x00000000 になる)。
pub fn comp_src_copy_cov(dst : UInt32, src : UInt32, cov : UInt32) -> UInt32 {
  let _ = dst
  apply_coverage(src, cov)
}

///|
/// SrcOver: `out_c = src_c + (dst_c * (256 - src_a)) >> 8`。
/// 上流 `build_src_over` と同じく AG/RB インターリーブで計算する。
/// src_a=0 → dst そのまま、src_a=255 → src で置換。
pub fn comp_src_over(dst : UInt32, src : UInt32) -> UInt32 {
  let mask : UInt32 = 0x00FF00FF
  let src_ag = (src >> 8) & mask
  let src_rb = src & mask
  let inv_alpha : UInt32 = 256 - ((src >> 24) & 0xFF)
  let dst_ag = (dst >> 8) & mask
  let dst_rb = dst & mask
  let out_ag = src_ag + (((dst_ag * inv_alpha) >> 8) & mask)
  let out_rb = src_rb + (((dst_rb * inv_alpha) >> 8) & mask)
  (out_ag << 8) | out_rb
}

///|
/// SrcOver + coverage。
/// `cov_src = div255(src * cov)` を新しい src として SrcOver を適用する
/// (上流 `build_src_over_cov` と同じ 3 ステップ)。
pub fn comp_src_over_cov(dst : UInt32, src : UInt32, cov : UInt32) -> UInt32 {
  comp_src_over(dst, apply_coverage(src, cov))
}

///|
/// Clear: dst を 0 にする。
pub fn comp_clear(dst : UInt32, src : UInt32) -> UInt32 {
  let _ = dst
  let _ = src
  0
}

///|
/// Clear + coverage。`out = (dst * (256 - cov)) >> 8`。
/// cov=255 → out=0、cov=0 → out=dst。
pub fn comp_clear_cov(dst : UInt32, src : UInt32, cov : UInt32) -> UInt32 {
  let _ = src
  if cov == 0xFF {
    return 0
  }
  let inv : UInt32 = 256 - (cov & 0xFF)
  let sc = fn(c : UInt32) -> UInt32 { (c * inv) >> 8 }
  (sc((dst >> 24) & 0xFF) << 24) |
  (sc((dst >> 16) & 0xFF) << 16) |
  (sc((dst >> 8) & 0xFF) << 8) |
  sc(dst & 0xFF)
}

///|
/// Plus: チャンネルごとに `min(src + dst, 255)` の saturating add。
pub fn comp_plus(dst : UInt32, src : UInt32) -> UInt32 {
  let a = @cmp.minimum(((src >> 24) & 0xFF) + ((dst >> 24) & 0xFF), 0xFF)
  let r = @cmp.minimum(((src >> 16) & 0xFF) + ((dst >> 16) & 0xFF), 0xFF)
  let g = @cmp.minimum(((src >> 8) & 0xFF) + ((dst >> 8) & 0xFF), 0xFF)
  let b = @cmp.minimum((src & 0xFF) + (dst & 0xFF), 0xFF)
  (a << 24) | (r << 16) | (g << 8) | b
}

///|
/// Plus + coverage。`cov_src = div255(src * cov)` を新しい src として
/// saturating add する (上流 `build_plus_cov` = 汎用 compose + cov)。
pub fn comp_plus_cov(dst : UInt32, src : UInt32, cov : UInt32) -> UInt32 {
  comp_plus(dst, apply_coverage(src, cov))
}

// ---------------------------------------------------------------------------
// 残りの Porter-Duff / ブレンド演算。
// 上流 `porter_duff.rs` / `blend_modes.rs` の compose_*_scalar を移植。
// 記法: sa/da = src/dst のアルファ、sc/dc = src/dst の各チャネル (0..=255)。
// 「f_c = dc + 1」系の因子と「256 - a」の逆アルファ因子は意図的に異なる
// (上流の式をそのまま使う)。
// ---------------------------------------------------------------------------

///|
/// packed 値から指定シフトのチャネルを取り出す。
fn ch(px : UInt32, shift : Int32) -> UInt32 {
  (px >> shift) & 0xFF
}

///|
/// 4 チャネルを packed ARGB に戻す。
fn pack4(a : UInt32, r : UInt32, g : UInt32, b : UInt32) -> UInt32 {
  (a << 24) | (r << 16) | (g << 8) | b
}

///|
/// 上流 `emit_srcover_alpha`: `out_a = sa + (da * (256 - sa)) >> 8`。
fn srcover_alpha(sa : UInt32, da : UInt32) -> UInt32 {
  sa + ((da * (256 - sa)) >> 8)
}

///|
/// 上流 `emit_blend_with_edges`: 分離ブレンド結果に端項を加える。
/// `out_c = blend_c + (sc * inv_da)>>8 + (dc * inv_sa)>>8`。
fn blend_with_edges(
  blend_c : UInt32,
  sc : UInt32,
  dc : UInt32,
  sa : UInt32,
  da : UInt32,
) -> UInt32 {
  blend_c + ((sc * (256 - da)) >> 8) + ((dc * (256 - sa)) >> 8)
}

///|
/// SrcIn: `out_c = (src_c * (dst_a + 1)) >> 8`。
pub fn comp_src_in(dst : UInt32, src : UInt32) -> UInt32 {
  let da = ch(dst, 24)
  let f = da + 1
  pack4(
    (ch(src, 24) * f) >> 8,
    (ch(src, 16) * f) >> 8,
    (ch(src, 8) * f) >> 8,
    (ch(src, 0) * f) >> 8,
  )
}

///|
/// SrcOut: `out_c = (src_c * (256 - dst_a)) >> 8`。
pub fn comp_src_out(dst : UInt32, src : UInt32) -> UInt32 {
  let inv : UInt32 = 256 - ch(dst, 24)
  pack4(
    (ch(src, 24) * inv) >> 8,
    (ch(src, 16) * inv) >> 8,
    (ch(src, 8) * inv) >> 8,
    (ch(src, 0) * inv) >> 8,
  )
}

///|
/// SrcAtop: `out_c = (src_c*(da+1))>>8 + (dst_c*(256-sa))>>8`。
pub fn comp_src_atop(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da_f = ch(dst, 24) + 1
  let inv_sa : UInt32 = 256 - sa
  pack4(
    ((sa * da_f) >> 8) + ((ch(dst, 24) * inv_sa) >> 8),
    ((ch(src, 16) * da_f) >> 8) + ((ch(dst, 16) * inv_sa) >> 8),
    ((ch(src, 8) * da_f) >> 8) + ((ch(dst, 8) * inv_sa) >> 8),
    ((ch(src, 0) * da_f) >> 8) + ((ch(dst, 0) * inv_sa) >> 8),
  )
}

///|
/// DstOver: `out_c = dst_c + (src_c * (256 - dst_a)) >> 8`。
pub fn comp_dst_over(dst : UInt32, src : UInt32) -> UInt32 {
  let inv : UInt32 = 256 - ch(dst, 24)
  pack4(
    ch(dst, 24) + ((ch(src, 24) * inv) >> 8),
    ch(dst, 16) + ((ch(src, 16) * inv) >> 8),
    ch(dst, 8) + ((ch(src, 8) * inv) >> 8),
    ch(dst, 0) + ((ch(src, 0) * inv) >> 8),
  )
}

///|
/// DstCopy: dst をそのまま残す (no-op)。
pub fn comp_dst_copy(dst : UInt32, src : UInt32) -> UInt32 {
  let _ = src
  dst
}

///|
/// DstIn: `out_c = (dst_c * (src_a + 1)) >> 8`。
pub fn comp_dst_in(dst : UInt32, src : UInt32) -> UInt32 {
  let f = ch(src, 24) + 1
  pack4(
    (ch(dst, 24) * f) >> 8,
    (ch(dst, 16) * f) >> 8,
    (ch(dst, 8) * f) >> 8,
    (ch(dst, 0) * f) >> 8,
  )
}

///|
/// DstOut: `out_c = (dst_c * (256 - src_a)) >> 8`。
pub fn comp_dst_out(dst : UInt32, src : UInt32) -> UInt32 {
  let inv : UInt32 = 256 - ch(src, 24)
  pack4(
    (ch(dst, 24) * inv) >> 8,
    (ch(dst, 16) * inv) >> 8,
    (ch(dst, 8) * inv) >> 8,
    (ch(dst, 0) * inv) >> 8,
  )
}

///|
/// DstAtop: `out_c = (dst_c*(sa+1))>>8 + (src_c*(256-da))>>8`。
pub fn comp_dst_atop(dst : UInt32, src : UInt32) -> UInt32 {
  let sa_f = ch(src, 24) + 1
  let inv_da : UInt32 = 256 - ch(dst, 24)
  pack4(
    ((ch(dst, 24) * sa_f) >> 8) + ((ch(src, 24) * inv_da) >> 8),
    ((ch(dst, 16) * sa_f) >> 8) + ((ch(src, 16) * inv_da) >> 8),
    ((ch(dst, 8) * sa_f) >> 8) + ((ch(src, 8) * inv_da) >> 8),
    ((ch(dst, 0) * sa_f) >> 8) + ((ch(src, 0) * inv_da) >> 8),
  )
}

///|
/// Xor: `out_c = (src_c*(256-da))>>8 + (dst_c*(256-sa))>>8`。
pub fn comp_xor(dst : UInt32, src : UInt32) -> UInt32 {
  let inv_sa : UInt32 = 256 - ch(src, 24)
  let inv_da : UInt32 = 256 - ch(dst, 24)
  pack4(
    ((ch(src, 24) * inv_da) >> 8) + ((ch(dst, 24) * inv_sa) >> 8),
    ((ch(src, 16) * inv_da) >> 8) + ((ch(dst, 16) * inv_sa) >> 8),
    ((ch(src, 8) * inv_da) >> 8) + ((ch(dst, 8) * inv_sa) >> 8),
    ((ch(src, 0) * inv_da) >> 8) + ((ch(dst, 0) * inv_sa) >> 8),
  )
}

///|
/// Minus: alpha は SrcOver 式、色は `max(dc - sc, 0)`。
pub fn comp_minus(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  pack4(
    srcover_alpha(sa, da),
    smax_u32(ch(dst, 16), ch(src, 16)),
    smax_u32(ch(dst, 8), ch(src, 8)),
    smax_u32(ch(dst, 0), ch(src, 0)),
  )
}

///|
/// `max(d - s, 0)` の飽和減算ヘルパ (チャネル値 0..=255 前提)。
fn smax_u32(d : UInt32, s : UInt32) -> UInt32 {
  if d > s {
    d - s
  } else {
    0
  }
}

///|
/// Modulate: `out_c = (src_c * (dst_c + 1)) >> 8` (alpha も同式)。
pub fn comp_modulate(dst : UInt32, src : UInt32) -> UInt32 {
  pack4(
    (ch(src, 24) * (ch(dst, 24) + 1)) >> 8,
    (ch(src, 16) * (ch(dst, 16) + 1)) >> 8,
    (ch(src, 8) * (ch(dst, 8) + 1)) >> 8,
    (ch(src, 0) * (ch(dst, 0) + 1)) >> 8,
  )
}

///|
/// Multiply: `blend_c = (sc*(dc+1))>>8`、alpha は SrcOver 式。
pub fn comp_multiply(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      (ch(src, 16) * (ch(dst, 16) + 1)) >> 8,
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      (ch(src, 8) * (ch(dst, 8) + 1)) >> 8,
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      (ch(src, 0) * (ch(dst, 0) + 1)) >> 8,
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// Screen: `out_c = sc + dc - (sc*(dc+1))>>8` (alpha も同式)。
pub fn comp_screen(dst : UInt32, src : UInt32) -> UInt32 {
  let scr = fn(sc : UInt32, dc : UInt32) -> UInt32 {
    sc + dc - ((sc * (dc + 1)) >> 8)
  }
  pack4(
    scr(ch(src, 24), ch(dst, 24)),
    scr(ch(src, 16), ch(dst, 16)),
    scr(ch(src, 8), ch(dst, 8)),
    scr(ch(src, 0), ch(dst, 0)),
  )
}

///|
/// Darken: `blend_c = min((sc*(da+1))>>8, (dc*(sa+1))>>8)`、edges 適用。
pub fn comp_darken(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  let da_p1 = da + 1
  let sa_p1 = sa + 1
  let blend = fn(sc : UInt32, dc : UInt32) -> UInt32 {
    @cmp.minimum((sc * da_p1) >> 8, (dc * sa_p1) >> 8)
  }
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      blend(ch(src, 16), ch(dst, 16)),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      blend(ch(src, 8), ch(dst, 8)),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      blend(ch(src, 0), ch(dst, 0)),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// Lighten: `blend_c = max((sc*(da+1))>>8, (dc*(sa+1))>>8)`、edges 適用。
pub fn comp_lighten(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  let da_p1 = da + 1
  let sa_p1 = sa + 1
  let blend = fn(sc : UInt32, dc : UInt32) -> UInt32 {
    @cmp.maximum((sc * da_p1) >> 8, (dc * sa_p1) >> 8)
  }
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      blend(ch(src, 16), ch(dst, 16)),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      blend(ch(src, 8), ch(dst, 8)),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      blend(ch(src, 0), ch(dst, 0)),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// Difference: `blend_c = |sc*(da+1)/256 - dc*(sa+1)/256|`、edges 適用。
pub fn comp_difference(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  let da_p1 = da + 1
  let sa_p1 = sa + 1
  let blend = fn(sc : UInt32, dc : UInt32) -> UInt32 {
    let a = (sc * da_p1) >> 8
    let b = (dc * sa_p1) >> 8
    if a > b {
      a - b
    } else {
      b - a
    }
  }
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      blend(ch(src, 16), ch(dst, 16)),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      blend(ch(src, 8), ch(dst, 8)),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      blend(ch(src, 0), ch(dst, 0)),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// Exclusion: `out_c = sc + dc - (2*sc*(dc+1))>>8`、alpha は SrcOver 式。
pub fn comp_exclusion(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  let excl = fn(sc : UInt32, dc : UInt32) -> UInt32 {
    sc + dc - ((sc * (dc + 1)) << 1 >> 8)
  }
  pack4(
    srcover_alpha(sa, da),
    excl(ch(src, 16), ch(dst, 16)),
    excl(ch(src, 8), ch(dst, 8)),
    excl(ch(src, 0), ch(dst, 0)),
  )
}

///|
/// Overlay: `2*dc < da` なら `(2*sc*(dc+1))>>8`、
/// そうでなければ `sa_da - (2*(sa-sc)*((da-dc)+1))>>8` (sa_da = (sa*(da+1))>>8)。
fn overlay_blend(
  sc : UInt32,
  dc : UInt32,
  sa : UInt32,
  da : UInt32,
  sa_da : UInt32,
) -> UInt32 {
  if dc << 1 < da {
    (sc * (dc + 1)) << 1 >> 8
  } else {
    sa_da - (((sa - sc) * (da - dc + 1)) << 1 >> 8)
  }
}

///|
/// Overlay ブレンド合成。
pub fn comp_overlay(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  let sa_da = (sa * (da + 1)) >> 8
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      overlay_blend(ch(src, 16), ch(dst, 16), sa, da, sa_da),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      overlay_blend(ch(src, 8), ch(dst, 8), sa, da, sa_da),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      overlay_blend(ch(src, 0), ch(dst, 0), sa, da, sa_da),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// HardLight: Overlay と同形で src/dst の役割を入れ替える。
/// `2*sc < sa` なら `(2*sc*(dc+1))>>8`、そうでなければ `sa_da - (2*(sa-sc)*((da-dc)+1))>>8`。
fn hard_light_blend(
  sc : UInt32,
  dc : UInt32,
  sa : UInt32,
  da : UInt32,
  sa_da : UInt32,
) -> UInt32 {
  if sc << 1 < sa {
    (sc * (dc + 1)) << 1 >> 8
  } else {
    sa_da - (((sa - sc) * (da - dc + 1)) << 1 >> 8)
  }
}

///|
/// HardLight ブレンド合成。
pub fn comp_hard_light(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  let sa_da = (sa * (da + 1)) >> 8
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      hard_light_blend(ch(src, 16), ch(dst, 16), sa, da, sa_da),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      hard_light_blend(ch(src, 8), ch(dst, 8), sa, da, sa_da),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      hard_light_blend(ch(src, 0), ch(dst, 0), sa, da, sa_da),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// PinLight: `2*sc < sa` なら `min(dc_sa, sc2_da)`、
/// そうでなければ `max(dc_sa, sc2_da - sa_da)`。
/// ここで `dc_sa = (dc*(sa+1))>>8`、`sc2_da = (2*sc*(da+1))>>8`。
fn pin_light_blend(
  sc : UInt32,
  dc : UInt32,
  sa : UInt32,
  da : UInt32,
  sa_da : UInt32,
) -> UInt32 {
  let dc_sa = (dc * (sa + 1)) >> 8
  let sc2_da = ((sc << 1) * (da + 1)) >> 8
  if sc << 1 < sa {
    @cmp.minimum(dc_sa, sc2_da)
  } else if sc2_da > sa_da + dc_sa {
    // smax(dc_sa, sc2_da - sa_da) と等価 (減算が非負の場合のみ採用)
    sc2_da - sa_da
  } else {
    dc_sa
  }
}

///|
/// PinLight ブレンド合成。
pub fn comp_pin_light(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  let sa_da = (sa * (da + 1)) >> 8
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      pin_light_blend(ch(src, 16), ch(dst, 16), sa, da, sa_da),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      pin_light_blend(ch(src, 8), ch(dst, 8), sa, da, sa_da),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      pin_light_blend(ch(src, 0), ch(dst, 0), sa, da, sa_da),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// LinearBurn: `out_c = max(sc + dc - sa_da, 0)`、alpha は SrcOver 式。
/// edges は適用しない (上流は直接結果を格納する)。
pub fn comp_linear_burn(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  let sa_da = (sa * (da + 1)) >> 8
  let burn = fn(sc : UInt32, dc : UInt32) -> UInt32 {
    let t = sc + dc
    if t > sa_da {
      t - sa_da
    } else {
      0
    }
  }
  pack4(
    srcover_alpha(sa, da),
    burn(ch(src, 16), ch(dst, 16)),
    burn(ch(src, 8), ch(dst, 8)),
    burn(ch(src, 0), ch(dst, 0)),
  )
}

///|
/// LinearLight: `blend_c = clamp(dc_sa + 2*sc_da - sa_da, 0, sa_da)`、edges 適用。
/// `dc_sa = (dc*(sa+1))>>8`、`sc_da = (sc*(da+1))>>8`。
fn linear_light_blend(
  sc : UInt32,
  dc : UInt32,
  sa : UInt32,
  da : UInt32,
  sa_da : UInt32,
) -> UInt32 {
  let dc_sa = (dc * (sa + 1)) >> 8
  let sc_da = (sc * (da + 1)) >> 8
  let unclamped = dc_sa + (sc_da << 1)
  if unclamped <= sa_da {
    0
  } else if unclamped - sa_da > sa_da {
    sa_da
  } else {
    unclamped - sa_da
  }
}

///|
/// LinearLight ブレンド合成。
pub fn comp_linear_light(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  let sa_da = (sa * (da + 1)) >> 8
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      linear_light_blend(ch(src, 16), ch(dst, 16), sa, da, sa_da),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      linear_light_blend(ch(src, 8), ch(dst, 8), sa, da, sa_da),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      linear_light_blend(ch(src, 0), ch(dst, 0), sa, da, sa_da),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// ColorDodge (スカラ経路): `blend_c = min(dc*sa / max(sa-sc, 1), da) * (sa+1) >> 8`。
/// 上流 `compose_color_dodge_scalar` と同じ整数演算。
/// sa < sc の場合 `sa - sc` は巨大値に wrap し、上流の umax と同じく
/// ratio=0 となる (denom が 1 になるのは sa == sc のときだけ)。
fn color_dodge_blend(
  sc : UInt32,
  dc : UInt32,
  sa : UInt32,
  da : UInt32,
) -> UInt32 {
  let denom = sa - sc
  let denom : UInt32 = if denom < 1 { 1 } else { denom }
  let ratio = dc * sa / denom
  let capped = @cmp.minimum(ratio, da)
  (capped * (sa + 1)) >> 8
}

///|
/// ColorDodge (SIMD 経路)。上流 `emit_color_dodge_blend_f32x4` は
/// f32 演算で `min(dc*sa / max(sa-sc, 1), da) * sa / 255` を計算し、
/// `fcvt_to_uint_sat` (0 方向への切り捨て + 飽和) で整数に戻す。
/// スカラ経路と結果が 1 LSB 異なり得るため別関数にしている。
fn color_dodge_blend_f32(
  sc : UInt32,
  dc : UInt32,
  sa : UInt32,
  da : UInt32,
) -> UInt32 {
  let sa_f = Float::from_uint(sa)
  let denom = Float::max(sa_f - Float::from_uint(sc), 1.0)
  let ratio = Float::from_uint(dc) * sa_f / denom
  let capped = Float::min(ratio, Float::from_uint(da))
  let blend = capped * sa_f / 255.0
  Float::max(blend, 0.0).to_int().reinterpret_as_uint()
}

///|
/// ColorDodge ブレンド合成。
pub fn comp_color_dodge(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      color_dodge_blend(ch(src, 16), ch(dst, 16), sa, da),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      color_dodge_blend(ch(src, 8), ch(dst, 8), sa, da),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      color_dodge_blend(ch(src, 0), ch(dst, 0), sa, da),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// ColorDodge ブレンド合成 (SIMD 経路)。JIT の I32X4 ループに対応し、
/// 1 ランの先頭 `count & ~3` ピクセルに使う。残りは `comp_color_dodge`。
pub fn comp_color_dodge_simd(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      color_dodge_blend_f32(ch(src, 16), ch(dst, 16), sa, da),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      color_dodge_blend_f32(ch(src, 8), ch(dst, 8), sa, da),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      color_dodge_blend_f32(ch(src, 0), ch(dst, 0), sa, da),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// ColorBurn (スカラ経路): `blend_c = max(da - sa*(da-dc)/max(sc,1), 0) * (sa+1) >> 8`。
fn color_burn_blend(
  sc : UInt32,
  dc : UInt32,
  sa : UInt32,
  da : UInt32,
) -> UInt32 {
  let denom : UInt32 = if sc < 1 { 1 } else { sc }
  let ratio = sa * (da - dc) / denom
  let inner = if da > ratio { da - ratio } else { 0 }
  (inner * (sa + 1)) >> 8
}

///|
/// ColorBurn (SIMD 経路)。上流 `emit_color_burn_blend_f32x4` は
/// `max(da - sa*(da-dc)/max(sc,1), 0) * sa / 255` を f32 で計算する。
fn color_burn_blend_f32(
  sc : UInt32,
  dc : UInt32,
  sa : UInt32,
  da : UInt32,
) -> UInt32 {
  let sa_f = Float::from_uint(sa)
  let da_f = Float::from_uint(da)
  let denom = Float::max(Float::from_uint(sc), 1.0)
  let ratio = sa_f * (da_f - Float::from_uint(dc)) / denom
  let inner = Float::max(da_f - ratio, 0.0)
  let blend = inner * sa_f / 255.0
  blend.to_int().reinterpret_as_uint()
}

///|
/// ColorBurn ブレンド合成。
pub fn comp_color_burn(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      color_burn_blend(ch(src, 16), ch(dst, 16), sa, da),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      color_burn_blend(ch(src, 8), ch(dst, 8), sa, da),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      color_burn_blend(ch(src, 0), ch(dst, 0), sa, da),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// ColorBurn ブレンド合成 (SIMD 経路)。`comp_color_dodge_simd` と同じく
/// 1 ランの先頭 `count & ~3` ピクセルに使う。
pub fn comp_color_burn_simd(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      color_burn_blend_f32(ch(src, 16), ch(dst, 16), sa, da),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      color_burn_blend_f32(ch(src, 8), ch(dst, 8), sa, da),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      color_burn_blend_f32(ch(src, 0), ch(dst, 0), sa, da),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// SoftLight の 1 チャネル分。上流は f32 演算なので Float で忠実に再現する。
/// 返り値は edges 適用前の blend 値。
fn soft_light_blend(
  sc : UInt32,
  dc : UInt32,
  sa : UInt32,
  da : UInt32,
) -> UInt32 {
  let sc_f = Float::from_uint(sc)
  let dc_f = Float::from_uint(dc)
  let sa_f = Float::from_uint(sa)
  let da_f = Float::from_uint(da)
  let two_f : Float = 2.0
  let four_f : Float = 4.0
  let twelve_f : Float = 12.0
  let sixteen_f : Float = 16.0
  let c255_f : Float = 255.0
  let two_sc = two_f * sc_f
  let da_safe = Float::max(da_f, 1.0)
  let dc_over_da = dc_f / da_safe
  let dc_sa = dc_f * sa_f
  let da_minus_dc = da_f - dc_f
  // Case 1
  let factor1 = sa_f - two_sc
  let blend1 = dc_sa - factor1 * dc_f * da_minus_dc / da_safe
  // Case 2: D*Da = ((16*Dc/Da-12)*Dc/Da+4)*Dc
  let d2 = (sixteen_f * dc_over_da - twelve_f) * dc_over_da + four_f
  let d2_da = d2 * dc_f
  // Case 3: D*Da = sqrt(Dc*Da)
  let d3_da = Float::sqrt(dc_f * da_f)
  // 内側条件 (4*Dc <= Da)
  let d_da = if four_f * dc_f <= da_f { d2_da } else { d3_da }
  // Cases 2&3
  let factor23 = two_sc - sa_f
  let blend23 = dc_sa + factor23 * (d_da - dc_f)
  // 外側条件 (2*Sc <= Sa)
  let blend = if two_sc <= sa_f { blend1 } else { blend23 }
  let blend = blend / c255_f
  let blend = Float::max(blend, 0.0)
  // fcvt_to_uint_sat: 切り捨て + 飽和 (ここでは負になり得ない)
  blend.to_int().reinterpret_as_uint()
}

///|
/// SoftLight ブレンド合成。
pub fn comp_soft_light(dst : UInt32, src : UInt32) -> UInt32 {
  let sa = ch(src, 24)
  let da = ch(dst, 24)
  pack4(
    srcover_alpha(sa, da),
    blend_with_edges(
      soft_light_blend(ch(src, 16), ch(dst, 16), sa, da),
      ch(src, 16),
      ch(dst, 16),
      sa,
      da,
    ),
    blend_with_edges(
      soft_light_blend(ch(src, 8), ch(dst, 8), sa, da),
      ch(src, 8),
      ch(dst, 8),
      sa,
      da,
    ),
    blend_with_edges(
      soft_light_blend(ch(src, 0), ch(dst, 0), sa, da),
      ch(src, 0),
      ch(dst, 0),
      sa,
      da,
    ),
  )
}

///|
/// 汎用 coverage 付き合成: `cov_src = div255(src*cov)` を新しい src として
/// comp_fn を適用する (上流 `build_generic_compose_cov` と同じ)。
/// SrcCopy/Clear/DstCopy のように cov で特別扱いされる op 以外で使う。
pub fn comp_generic_cov(
  comp_fn : (UInt32, UInt32) -> UInt32,
  dst : UInt32,
  src : UInt32,
  cov : UInt32,
) -> UInt32 {
  comp_fn(dst, apply_coverage(src, cov))
}

// ---------------------------------------------------------------------------
// A8 宛先のスカラ合成 (上流 pipeline/a8.rs に対応)
// 4bpp 系と式が異なる点に注意: ここでは本物の /255 除算を使う。
// ---------------------------------------------------------------------------

///|
/// A8 SrcOver。`out = sa + (d * (255 - sa)) / 255`。
pub fn a8_src_over(d : UInt32, src : UInt32) -> UInt32 {
  let sa = (src >> 24) & 0xFF
  if sa == 0 {
    d
  } else if sa == 255 {
    255
  } else {
    @cmp.minimum(sa + d * (255 - sa) / 255, 255)
  }
}

///|
/// A8 SrcCopy。src のアルファチャネルをそのまま書き込む。
pub fn a8_src_copy(d : UInt32, src : UInt32) -> UInt32 {
  let _ = d
  (src >> 24) & 0xFF
}

///|
/// A8 Clear。0 を書き込む。
pub fn a8_clear(d : UInt32, src : UInt32) -> UInt32 {
  let _ = d
  let _ = src
  0
}

///|
/// A8 Plus。`out = min(sa + d, 255)`。
pub fn a8_plus(d : UInt32, src : UInt32) -> UInt32 {
  let sa = (src >> 24) & 0xFF
  @cmp.minimum(sa + d, 255)
}
