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

## Cameras

The resource `hxn.me.gpu.Cameras` holds the cameras that renderers draw
through, the same cameras for 2D and 3D. The world has y up, as in
`hxnme-physics`, and 2D content lies in its XY plane. Each `Camera` sits at
`x`, `y`, `z`, turned by the quaternion `rx`, `ry`, `rz`, `rw`, and looks
along its -z. `roll(angle)` turns it about the z axis, as a 2D camera turns.

| Projection | View |
|---|---|
| `Orthographic(height, near, far)` | Things keep their size at any distance. The view is `height` world units high, or one unit for each logical pixel when `height` is 0. This is the default, for 2D. |
| `Perspective(fovY, near, far)` | Things farther away look smaller, with the vertical field of view `fovY` in radians. |
| `Screen` | Logical pixels, with the origin at the top-left corner and y down, for UI and HUDs. `x` and `y` move the view. |

| Field | Effect |
|---|---|
| `viewport` | The part of the target that the view covers, each part from 0 to 1, for split screens. |
| `target` | The render target to draw into, set before the first frame. Without it, the camera draws into the frame. |
| `clear` | The color that the camera's render target is cleared to, or null to keep it. |
| `order` | Cameras draw from the lowest `order` up. |
| `layers` | The layer bits the camera shows. Renderers give their content layers, and each camera draws only the content it shows. |
| `depth` | Whether renderers test and write depth for what the camera shows, so nearer content hides farther content in any drawing order, such as planes that intersect. Off by default, so later content draws over earlier content. |

`Cameras.main` is the camera that the app starts with. `cameras.add(camera)`
adds another, for example a screen camera for the UI on layer 2:

```haxe
var ui = new Camera();
ui.projection = Screen;
ui.layers = 2;
ui.order = 1;
cameras.add(ui);
```

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
- With `pass.depth`, a pass tests and writes depth in a `Depth32Float`
  texture of its target's size, which the graph keeps for the frame and for
  each render target. The first pass of a frame that uses it clears it to 1.
- `RenderTarget(width, height)` has a fixed size. `RenderTarget.ofFrame(scale)`
  follows the frame's size. The graph makes its texture when the device is
  open, and makes it again when the size changes.
- Render pipelines that draw into the frame use `gpu.format`.

## Checks

In `tests/gpu`, run `hxn check hl cpp cppia app.hxml --vm ash`. The check
opens a hidden window, clears a render target and the frame for three
frames, and reads the render target back.
