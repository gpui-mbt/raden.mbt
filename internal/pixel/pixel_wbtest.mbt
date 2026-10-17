///|
/// パックドピクセル演算のテスト。
/// 期待値は上流 `core_pipelines.rs` / `porter_duff.rs` / `pixel/mod.rs` の
/// 整数式を手計算したもの。JIT の AG/RB パッキングと結果が一致することを確認する。

///|
/// premultiply_rgba: 上流 `(c * a + 128) / 255` の整数除算丸め。
test "premultiply_rgba は上流の丸めと一致する" {
  // a=128: r=(255*128+128)/255=128, g=(128*128+128)/255=64, b=0
  inspect(
    premultiply_rgba(255, 128, 0, 128).to_string(radix=16),
    content="80804000",
  )
  // 不透明入力はそのまま 0xAARRGGBB。
  inspect(
    premultiply_rgba(255, 128, 64, 255).to_string(radix=16),
    content="ffff8040",
  )
  // a=0 は全チャネル 0。
  inspect(premultiply_rgba(255, 255, 255, 0).to_string(radix=16), content="0")
  // premultiplied 不変条件: 各チャネルは alpha 以下。
  let px = premultiply_rgba(200, 100, 50, 96)
  let a_ok = ((px >> 16) & 0xFF) <= 96 &&
    ((px >> 8) & 0xFF) <= 96 &&
    (px & 0xFF) <= 96
  assert_eq(a_ok, true)
}

///|
/// alpha_to_u8: 上流 `(a * 255.0 + 0.5) as u8` の切り捨て丸め。
/// 非有限値・負値は 0、1.0 以上は 255 にクランプする (移植版の安全化)。
test "alpha_to_u8 のクランプと丸め" {
  assert_eq(alpha_to_u8(1.0), 255)
  assert_eq(alpha_to_u8(0.5), 128)
  assert_eq(alpha_to_u8(0.0), 0)
  assert_eq(alpha_to_u8(-1.0), 0)
  assert_eq(alpha_to_u8(2.0), 255)
  assert_eq(alpha_to_u8(@double.not_a_number), 0)
  assert_eq(alpha_to_u8(@double.infinity), 0)
}

///|
/// scale_prgb32: `(v*a + 0x80 + ((v*a + 0x80) >> 8)) >> 8` の近似除算。
test "scale_prgb32 は上流近似式と一致する" {
  // px=0xFF804020, a=128:
  //   A: (255*128+128)=32768 → (32768+128)>>8 = 128
  //   R: (128*128+128)=16512 → (16512+64)>>8 = 64
  //   G: (64*128+128)=8320  → (8320+32)>>8 = 32
  //   B: (32*128+128)=4224  → (4224+16)>>8 = 16
  inspect(scale_prgb32(0xFF804020, 128).to_string(radix=16), content="80402010")
  // alpha=255 は恒等、alpha=0 は 0。
  assert_eq(scale_prgb32(0xFF804020, 255), 0xFF804020)
  assert_eq(scale_prgb32(0xFF804020, 0), 0)
}

///|
/// SrcCopy 系: cov なしは src そのまま、cov ありは div255 スケールで dst 無視。
test "comp_src_copy 系" {
  assert_eq(comp_src_copy(0xDEADBEEF, 0x80402010), 0x80402010)
  // cov=128: div255(128*128)=64, div255(64*128)=32, div255(32*128)=16, div255(16*128)=8
  assert_eq(comp_src_copy_cov(0xDEADBEEF, 0x80402010, 128), 0x40201008)
  // cov=0 は dst を残さず 0 を書く (上流 SrcCopy+cov の挙動)。
  assert_eq(comp_src_copy_cov(0xDEADBEEF, 0x80402010, 0), 0)
}

///|
/// SrcOver: `out_c = src_c + (dst_c * (256 - src_a)) >> 8`。
test "comp_src_over は上流式と一致する" {
  // src=dst=0x80402010, inv=128:
  //   A: 128 + (128*128>>8)=192, R: 64+(64*128>>8)=96, G: 32+16=48, B: 16+8=24
  inspect(
    comp_src_over(0x80402010, 0x80402010).to_string(radix=16),
    content="c0603018",
  )
  // 不透明 src は dst を完全に置き換える。
  assert_eq(comp_src_over(0xDEADBEEF, 0xFF804020), 0xFF804020)
  // 完全透明 src は dst をそのまま返す。
  assert_eq(comp_src_over(0xDEADBEEF, 0x00000000), 0xDEADBEEF)
}

///|
/// SrcOver + coverage: `cov_src = div255(src*cov)` を先に計算してから SrcOver。
test "comp_src_over_cov は上流 3 ステップと一致する" {
  // cov=128 で src=0x80402010 → cov_src=0x40201008 (上記と同じ計算)。
  // dst=0x80402010, inv=256-64=192:
  //   A: 64 + (128*192>>8)=160, R: 32+(64*192>>8)=80, G: 16+24=40, B: 8+12=20
  inspect(
    comp_src_over_cov(0x80402010, 0x80402010, 128).to_string(radix=16),
    content="a0502814",
  )
  // cov=0 は dst 不変。
  assert_eq(comp_src_over_cov(0xDEADBEEF, 0x80402010, 0), 0xDEADBEEF)
  // cov=255 は cov なしと同じ。
  assert_eq(
    comp_src_over_cov(0x80402010, 0x80402010, 255),
    comp_src_over(0x80402010, 0x80402010),
  )
}

///|
/// Clear 系: cov=255→0、cov=0→dst、中間は `dst * (256 - cov) >> 8`。
test "comp_clear 系" {
  assert_eq(comp_clear(0xDEADBEEF, 0x80402010), 0)
  assert_eq(comp_clear_cov(0xC0603018, 0x80402010, 255), 0)
  assert_eq(comp_clear_cov(0xC0603018, 0x80402010, 0), 0xC0603018)
  // cov=128: inv=128 → A:192*128>>8=96, R:96*128>>8=48, G:48*128>>8=24, B:24*128>>8=12
  inspect(
    comp_clear_cov(0xC0603018, 0x80402010, 128).to_string(radix=16),
    content="6030180c",
  )
}

///|
/// Plus 系: チャネルごとの飽和加算。cov ありは div255 スケール後に加算。
test "comp_plus 系" {
  assert_eq(comp_plus(0xF0E0D0C0, 0x80F0A050), 0xFFFFFFFF)
  assert_eq(comp_plus(0x10203040, 0x05060708), 0x15263748)
  // cov=128 で src=0x80402010 → cov_src=0x40201008 を飽和加算:
  //   A: min(64+128,255)=192, R: min(32+64,255)=96, G: 48, B: 24
  inspect(
    comp_plus_cov(0x80402010, 0x80402010, 128).to_string(radix=16),
    content="c0603018",
  )
}

///|
/// A8 宛先: 4bpp 系と式が違い、本物の /255 除算を使う点に注意。
test "A8 宛先の合成" {
  // sa=51, d=100 → 51 + 100*204/255 = 51 + 80 = 131
  assert_eq(a8_src_over(100, 0x33000000), 131)
  // sa=0 → d、sa=255 → 255。
  assert_eq(a8_src_over(100, 0), 100)
  assert_eq(a8_src_over(100, 0xFF000000), 255)
  assert_eq(a8_src_copy(100, 0x33000000), 0x33)
  assert_eq(a8_clear(100, 0x33000000), 0)
  assert_eq(a8_plus(200, 0x64000000), 255)
  assert_eq(a8_plus(100, 0x32000000), 150)
}

///|
/// 全 29 CompOp の合成関数をオラクル由来ベクトルで検証する。
/// 期待値は `conformance/fixtures/comp_ops_box_8x29.json` (8x29 Prgb32、
/// dst=premult(60,120,180,200)=0xC82F5E8D、src=premult(200,100,50,128)=0x80643219)
/// の Rust オラクル出力の各行先頭ピクセル。
/// 幅 8 は 4 の倍数なので全ピクセルが SIMD 経路扱いになる。
test "全 CompOp: オラクル由来ベクトル" {
  let d : UInt32 = 0xC82F5E8D
  let s : UInt32 = 0x80643219
  assert_eq(comp_src_over(d, s), 0xE47B615F)
  assert_eq(comp_src_copy(d, s), 0x80643219)
  assert_eq(comp_src_in(d, s), 0x644E2713)
  assert_eq(comp_src_out(d, s), 0x1C150A05)
  assert_eq(comp_src_atop(d, s), 0xC8655659)
  assert_eq(comp_dst_over(d, s), 0xE4446892)
  assert_eq(comp_dst_copy(d, s), 0xC82F5E8D)
  assert_eq(comp_dst_in(d, s), 0x64172F47)
  assert_eq(comp_dst_out(d, s), 0x64172F46)
  assert_eq(comp_dst_atop(d, s), 0x802C394C)
  assert_eq(comp_xor(d, s), 0x802C394B)
  assert_eq(comp_clear(d, s), 0x00000000)
  assert_eq(comp_plus(d, s), 0xFF9390A6)
  assert_eq(comp_minus(d, s), 0xE4002C74)
  assert_eq(comp_modulate(d, s), 0x6412120D)
  assert_eq(comp_multiply(d, s), 0xE43E4B58)
  assert_eq(comp_screen(d, s), 0xE4817E99)
  assert_eq(comp_overlay(d, s), 0xE4515E7F)
  assert_eq(comp_darken(d, s), 0xE443605E)
  assert_eq(comp_lighten(d, s), 0xE47A6892)
  // ColorDodge/ColorBurn の行は上流の SIMD (f32) 経路の値。
  assert_eq(comp_color_dodge_simd(d, s), 0xE49086A2)
  assert_eq(comp_color_burn_simd(d, s), 0xE42E394B)
  assert_eq(comp_linear_burn(d, s), 0xE42F2C42)
  assert_eq(comp_linear_light(d, s), 0xE47B5254)
  assert_eq(comp_pin_light(d, s), 0xE4656872)
  assert_eq(comp_hard_light(d, s), 0xE46F5E66)
  assert_eq(comp_soft_light(d, s), 0xE4516285)
  assert_eq(comp_difference(d, s), 0xE463417F)
  assert_eq(comp_exclusion(d, s), 0xE46E6B8B)
}

///|
/// ColorDodge/ColorBurn はスカラ末尾経路が整数演算で SIMD (f32) と
/// 1 LSB 異なり得る。両経路を区別して検証する。
/// 値は上流 compose_*_scalar の整数式をそのまま手計算したもの:
///   dodge B: min(141*128/103, 200)=175 → (175*129)>>8=88 → 88+5+70=163
///   burn  はこの入力では両経路一致 (0xE42E394B)。
test "ColorDodge/ColorBurn: スカラ経路との差分" {
  let d : UInt32 = 0xC82F5E8D
  let s : UInt32 = 0x80643219
  // スカラ (整数) 経路: B チャネルが 0xA2 ではなく 0xA3 になる。
  assert_eq(comp_color_dodge(d, s), 0xE49086A3)
  assert_eq(comp_color_burn(d, s), 0xE42E394B)
  // SIMD 経路とは dst/src ともに同じ入力で 1 LSB だけ異なる。
  assert_eq(comp_color_dodge_simd(d, s), 0xE49086A2)
}
