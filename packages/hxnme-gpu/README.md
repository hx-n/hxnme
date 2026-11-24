# hxnme-gpu

hxnme-gpu draws the frames of an hxnme app with the GPU. Its package is
`hxn.me.gpu`. The plugin opens [hxn-gpu](https://github.com/hx-n/hxn-gpu)
on the app's window from `hxnme-window`. In each frame, it draws a frame
graph, which is the ordered list of passes that draw the frame. The 2D
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
draws with WebGL2. If a target needs other drivers, the app replaces the
list for that target in `hxnme.toml`. Each key is part of a target triple:

```toml
[libraries.hxnme-gpu]
windows = ["hxn-gpu-d3d12", "hxn-gpu-gles"]
```

## Frames

The resource `hxn.me.gpu.Gpu` holds the device. The plugin starts to open
the device in the first frame. The device is ready some frames later,
because the open settles asynchronously. Until then, `gpu.ready()` is false
and the plugin draws no frame. If no driver opens, `gpu.failure` holds the
reason.

In each frame after that, the system `prepare` runs in `Begin`. It sizes
the surface to the window and takes the window's next frame as `gpu.frame`.
The
system `present` draws the passes into it and presents it in `Render`.
Systems in `Render` that change what the passes draw set
`before = hxn.me.gpu.GpuPlugin.present`, so they run before `present`. The
plugin draws no frame while the app is suspended.

| Key | Effect |
|---|---|
| `gpu.vsync` | Whether each frame waits for the display's refresh to show. The default is `true`. The plugin copies it to `Display.vsync`, and the window host then leaves the pacing of frames to the present. |

## Cameras

The resource `hxn.me.gpu.Cameras` holds the cameras that renderers draw
through. 2D and 3D use the same cameras. The world has y up, as in
`hxnme-physics`, and 2D content lies in its XY plane. Each `Camera` sits at
`x`, `y`, `z`, and the quaternion `rx`, `ry`, `rz`, `rw` turns it. It looks
along its -z. `roll(angle)` turns it about the z axis, as a 2D camera turns.

| Projection | View |
|---|---|
| `Orthographic(height, near, far)` | Things keep their size at any distance. The view is `height` world units high. When `height` is 0, the view shows one unit for each logical pixel. This is the default, for 2D. |
| `Perspective(fovY, near, far)` | Things farther away look smaller, with the vertical field of view `fovY` in radians. |
| `Screen` | Logical pixels, with the origin at the top-left corner and y down, for UI and HUDs. `x` and `y` move the view. |

| Field | Effect |
|---|---|
| `viewport` | The part of the target that the view covers, each part from 0 to 1, for split screens. |
| `target` | The render target to draw into, set before the first frame. Without it, the camera draws into the frame. |
| `clear` | The color that the camera clears its render target to, or null to keep what the target holds. |
| `order` | Cameras draw from the lowest `order` up. |
| `layers` | The layer bits the camera shows. Renderers give their content layers, and each camera draws only the content it shows. |
| `depth` | Whether renderers test and write depth for what the camera shows. With depth, nearer content hides farther content in any drawing order, such as planes that intersect. The default is off, so later content draws over earlier content. |

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

Passes run from the lowest `order` up. Passes with the same order run in
the order that they were added. The graph records all passes of a frame
into one command encoder and submits them together.

- The first pass into the frame clears it to `gpu.clear`, unless it sets
  `pass.clear`. Later passes into the frame draw over it.
- Each pass into a render target clears it to `pass.clear`, which is
  transparent black by default. With `pass.keep`, the pass draws over the
  target instead.
- With `pass.depth`, a pass tests and writes depth in a `Depth32Float`
  texture of its target's size, which the graph keeps for the frame and for
  each render target. The first pass of a frame that uses it clears it to 1.
- `RenderTarget(width, height)` has a fixed size. `RenderTarget.ofFrame(scale)`
  follows the frame's size. After the device opens, the graph makes the
  target's texture. If the size changes, the graph makes the texture again.
- Render pipelines that draw into the frame use `gpu.format`.

## Checks

In `tests/gpu`, run `hxn check hl cpp cppia app.hxml --vm ash`. The check
opens a hidden window, clears a render target and the frame for three
frames, and reads the render target back.

In `tests/pacing`, run the same command. The check opens a visible window,
because a hidden window does not wait for the refresh. It presents with
vsync and records how long each frame takes after the first 30 frames. The
check passes under two conditions. The mean frame time is within a tenth of
the refresh period. Fewer than one frame in twenty take more than one and a
half periods.
