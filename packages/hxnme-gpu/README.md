# hxnme-gpu

The GPU of an hxnme app, in `hxn.me.gpu`. The plugin opens
[hxn-gpu](https://github.com/hx-n/hxn-gpu) on the app's window from
`hxnme-window`, and draws a frame graph of passes into each frame. The 2D
renderer, the UI and 3D add their passes to the same graph.

List both plugins in the app's `hxnme.toml`:

```toml
plugins = ["hxnme-window", "hxnme-gpu"]
```

## Drivers

The plugin compiles in the modern driver of each target, and the driver
that each target falls back to:

| Target | Drivers |
|---|---|
| macOS and iOS | Metal |
| Windows | Direct3D 12 |
| Linux and Android | Vulkan, then OpenGL ES |
| Web page | WebGPU, then WebGL2 |

hxn-gpu opens the first driver that works, so a browser without WebGPU
draws with WebGL2. For a target that needs other drivers, the app replaces
the list for that target in `hxnme.toml`. Each key is part of a target
triple:

```toml
[libraries.hxnme-gpu]
windows = ["hxn-gpu-d3d12", "hxn-gpu-gles"]
```

## Frames

The resource `hxn.me.gpu.Gpu` holds the device. The device opens in the
first frame and is ready some frames later, because opening it settles
asynchronously. Until then `gpu.ready()` is false and no frame is drawn. If
no driver opens, `gpu.failure` gives the reason.

In each frame after that, the system `prepare` sizes the surface to the
window and takes the window's next frame in `Begin`, as `gpu.frame`. The
system `present` draws the passes into it and presents it in `Render`.
Systems in `Render` that change what the passes draw run before it, with
`before = hxn.me.gpu.GpuPlugin.present`. No frame is drawn while the app is
suspended.

| Key | Effect |
|---|---|
| `gpu.vsync` | Whether each frame waits for the display's refresh to show. The default is `true`. |

## Passes

Add a pass to `gpu.graph` once, for example in a `Start` system. It runs in
every frame while `pass.enabled` is true:

```haxe
@:system(Start)
static function setup(gpu:ResMut<Gpu>) {
	var scene = RenderTarget.ofFrame(0.5);
	var world = new Pass("world", scene, (pass, into) -> {
		// record draws into the half-size target
	});
	gpu.graph.add(world);
	gpu.graph.add(new Pass("compose", null, (pass, into) -> {
		// sample scene.texture into the frame
	}, 10));
}
```

Passes run from the lowest `order` up, and in the order they were added
within one order. All passes of a frame go into one command encoder and one
submission.

- The first pass into the frame clears it to `gpu.clear`, unless it sets
  `pass.clear`. Later passes into the frame draw over it.
- Each pass into a render target clears it to `pass.clear`, transparent
  black by default, or draws over it with `pass.keep`.
- `RenderTarget(width, height)` has a fixed size. `RenderTarget.ofFrame(scale)`
  follows the frame's size. The graph makes its texture when the device is
  open, and makes it again when the size changes.
- Render pipelines that draw into the frame use `gpu.format`.

## Checks

In `tests/gpu`, run `hxn check hl cpp cppia app.hxml --vm ash`. The check
opens a hidden window, clears a render target and the frame for three
frames, and reads the render target back.
