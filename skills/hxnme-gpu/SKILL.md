---
name: hxnme-gpu
description: Draw an hxnme app's frames with the hxnme-gpu haxelib (package `hxn.me.gpu`), the GPU plugin of the hxn media engine, over hxn-gpu on HashLink, Ash, hxcpp and CPPIA. Use when an app or plugin draws with the GPU, adds passes or render targets to the frame graph, chooses GPU drivers per target, or when changing the plugin itself.
---

# hxnme-gpu

## Setup

```toml
plugins = ["hxnme-window", "hxnme-gpu"]

[gpu]
vsync = true
```

The plugin brings each target's drivers: Metal on Apple platforms, Direct3D
12 on Windows, Vulkan then OpenGL ES on Linux and Android, WebGPU then WebGL2
in a web page. Replace a target's list in hxnme.toml, by a fragment of the
target triple: `[libraries.hxnme-gpu]` with `windows = ["hxn-gpu-d3d12",
"hxn-gpu-gles"]`.

## Use

`Res<hxn.me.gpu.Gpu>` holds `device`, `surface`, `frame` (the texture of
this frame, from `Begin` to the end of `Render`), `format` (for pipelines
that draw into the frame), `clear`, `graph`, `presented` and `failure`. The
device opens in the first frame and settles some frames later: check
`gpu.ready()` before making pipelines or buffers.

```haxe
@:system(Start)
static function setup(gpu:ResMut<Gpu>) {
	var target = new RenderTarget(256, 256);          // or RenderTarget.ofFrame(0.5)
	var pass = new Pass("world", target, (pass, into) -> draw(pass));
	pass.clear = {r: 0, g: 0, b: 0, a: 1};            // a target clears to transparent black by default
	gpu.graph.add(pass);
	gpu.graph.add(new Pass("compose", null, (pass, into) -> compose(pass), 10));
}
```

Rules:

- Passes run by `order`, then in the order added. The first frame pass
  clears the frame to `gpu.clear` unless it sets `clear`; later frame passes
  draw over it. Target passes with `keep` draw over their target.
- Add passes once; toggle `pass.enabled`. Drawing a frame allocates no pass.
- Systems in `Render` that change what passes draw add
  `before = hxn.me.gpu.GpuPlugin.present`.
- Frames on Metal cannot be read back; read a render target instead.

## Checks

```
cd tests/gpu && hxn check hl cpp cppia app.hxml --vm ash
```

Follow the [hxnme agent rules](https://github.com/hx-n/hxnme/blob/main/AGENTS.md),
the [kernel skill](https://github.com/hx-n/hxnme/blob/main/skills/hxnme/SKILL.md)
and the [hxn-gpu skill](https://github.com/hx-n/hxn-gpu/blob/main/skills/hxn-gpu/SKILL.md).
