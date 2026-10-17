///|
/// scene の決定性テスト。
/// oracle (上流 Rust scene) が生成した canonical RGBA8 の sha256 と
/// 一致することを Native/JS 両ターゲットで検証する。
/// 期待値は examples/manifest.json の raw_sha256 と同一。
/// (同じ scene・同じ size・同じ frame → ターゲット非依存で同一バイト列)

///|
test "basic_drawing の canonical 出力が oracle と一致する" {
  let raw = render_to_rgba8(BasicDrawing, 1280, 720, 0.0) catch {
    e => fail("\{e}")
  }
  // manifest.json: basic_drawing.raw_sha256
  inspect(
    @sha256.sha256_hex(raw[:]),
    content="c3b545fd6edc87b21a5761e8b0a9a9ceda77be9aa21915607fad17619694ebe4",
  )
}

///|
test "gradient_drawing の canonical 出力が oracle と一致する" {
  let raw = render_to_rgba8(GradientDrawing, 1280, 720, 0.0) catch {
    e => fail("\{e}")
  }
  inspect(
    @sha256.sha256_hex(raw[:]),
    content="61fd7aa9d49466ebcef192871e5688d5e0d278484fb755ffd10950a9cb79fab7",
  )
}

///|
test "stroke_drawing の canonical 出力が oracle と一致する" {
  let raw = render_to_rgba8(StrokeDrawing, 1280, 720, 0.0) catch {
    e => fail("\{e}")
  }
  inspect(
    @sha256.sha256_hex(raw[:]),
    content="19c4eec073c2bdb198e37f874ceabc9c1ca509606b349302ffc7276be842de82",
  )
}

///|
test "blit_clip_pattern_paths の canonical 出力が oracle と一致する" {
  // 拡張パス命令 (smooth / conic / arc_to) もここで間接的に検証される。
  let raw = render_to_rgba8(BlitClipPatternPaths, 1280, 720, 0.0) catch {
    e => fail("\{e}")
  }
  inspect(
    @sha256.sha256_hex(raw[:]),
    content="96afedf5b80a3493c80f78cc8dd7c4f4d05e1968773895b28471188094627f24",
  )
}

///|
test "animation は frame/fps で決定的な出力になる" {
  // t = frame / fps。frame 0/30 で oracle と一致する。
  let raw0 = render_to_rgba8(Animation, 1280, 720, animation_t(0, 60)) catch {
    e => fail("\{e}")
  }
  inspect(
    @sha256.sha256_hex(raw0[:]),
    content="c8d67c2973499b766318e8599076787f84acec63a01535fc5dfe508f0306aa66",
  )
  let raw30 = render_to_rgba8(Animation, 1280, 720, animation_t(30, 60)) catch {
    e => fail("\{e}")
  }
  inspect(
    @sha256.sha256_hex(raw30[:]),
    content="e26390f92fa19a7a217e09ca9ef8e279b42e76ee0789449e3c8b717518116cc7",
  )
  // 別サイズ (640x360) でも決定的。
  let raw90 = render_to_rgba8(Animation, 640, 360, animation_t(90, 60)) catch {
    e => fail("\{e}")
  }
  inspect(
    @sha256.sha256_hex(raw90[:]),
    content="407d47aa55b532e753eb4b1e1cc55235ade71342ae2e5b37bb9c51dc02baf20c",
  )
}

///|
test "未知の scene 名は InvalidInput で失敗する" {
  // 未対応 scene が暗黙の成功にならないことを確認。
  try SceneName::parse("nonexistent") |> ignore catch {
    e => inspect(e, content="InvalidInput(unknown scene: nonexistent)")
  } noraise {
    _ => fail("expected InvalidInput")
  }
}
