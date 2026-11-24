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

The plugin brings each target's drivers. Apple platforms get Metal, and
Windows gets Direct3D 12. Linux and Android get Vulkan then OpenGL ES, and
a web page gets WebGPU then WebGL2. To replace a target's list, set it in
the `[libraries.hxnme-gpu]` table of hxnme.toml. Its key is part of the
target triple, such as `windows = ["hxn-gpu-d3d12", "hxn-gpu-gles"]`.

## Use

`Res<hxn.me.gpu.Gpu>` holds `device`, `surface`, `frame`, `format`,
`clear`, `graph`, `presented` and `failure`. `frame` is the texture of this
frame, from `Begin` to the end of `Render`. Pipelines that draw into the
frame use `format`. The device opens in the first frame and settles some
frames later. Before you make pipelines or buffers, make sure that
`gpu.ready()` returns true.

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

`Res<hxn.me.gpu.Cameras>` holds the cameras, which 2D and 3D share. It has
`main` and `add(camera)`. The world has y up, as in physics, and 2D lies in
the XY plane. Each `Camera` has `x`, `y`, `z` and a quaternion `rx`, `ry`,
`rz`, `rw`, which `roll(angle)` can also set. It looks along -z. Its
`projection` is `Orthographic(height, near, far)`,
`Perspective(fovY, near, far)` or `Screen`. The default is orthographic,
and height 0 shows one unit for each logical pixel. `Screen` shows logical
pixels from the top left with y down, for UI. Each camera also has
`viewport` (parts from 0 to 1), `target`, `clear`, `order`, `layers` (the
bits of the content it shows) and `depth`. With `depth`, renderers test and
write depth for the camera. It is off by default. `pass.depth` gives a pass
a depth texture of its target's size. The frame's first pass that uses the
texture clears it. `camera.writeMatrix(width, height, out)` gives the
world-to-clip matrix, column after column.

Rules:

- Passes run by `order`, then in the order that they were added. The first
  pass into the frame clears it to `gpu.clear`, unless the pass sets
  `clear`. Later passes into the frame draw over it. Passes into a render
  target with `keep` draw over their target.
- Add each pass once, and turn it on and off with `pass.enabled`. Drawing a
  frame allocates no pass.
- Systems in `Render` that change what the passes draw add
  `before = hxn.me.gpu.GpuPlugin.present`.
- On Metal, the app cannot read a frame back. Read a render target instead.

## Checks

```
cd tests/gpu && hxn check hl cpp cppia app.hxml --vm ash
```

Follow the [hxnme agent rules](https://github.com/hx-n/hxnme/blob/main/AGENTS.md),
the [kernel skill](https://github.com/hx-n/hxnme/blob/main/skills/hxnme/SKILL.md)
and the [hxn-gpu skill](https://github.com/hx-n/hxn-gpu/blob/main/skills/hxn-gpu/SKILL.md).
