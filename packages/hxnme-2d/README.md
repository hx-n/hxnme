# hxnme-2d

The 2D renderer of an hxnme app, in `hxn.me.render2d`. It draws sprites and
shapes with one instanced shader, through the frame graph of `hxnme-gpu`.
Shapes take their edges from signed distance functions, so they stay smooth
at any size, zoom and angle.

```toml
plugins = ["hxnme-window", "hxnme-gpu", "hxnme-2d"]
```

## Coordinates

The renderer draws through the cameras of `hxnme-gpu`, the same cameras
that 3D uses. The world has y up, as in `hxnme-physics`, and 2D content
lies in its XY plane, so sprites and physics bodies share coordinates. The
main camera is orthographic, with one world unit for each logical pixel,
centered on its `x` and `y`. Cameras with the `Screen` projection show
logical pixels with the origin at the top left and y down, for UI and HUDs.

Each shape's `x`, `y` is its corner with the smaller coordinates: the
bottom-left corner in the world, and the top-left corner through a screen
camera. Images and rounded corners stay upright through both.

`draw.layer` sets the layer bits of what is added next, 1 by default. Each
camera draws only the layers in its `layers`, so a screen camera on layer 2
can draw the UI over the world:

```haxe
draw.layer = 1;
draw.sprite(hero, heroX, heroY, 32, 32);
draw.layer = 2;
draw.rect(16, 16, 200, 24, 0x202020, 0.8, 6);   // a bar in the UI
```

## Drawing

Systems draw through the resource `Draw` in each frame. The renderer
draws what they add, in the order they add it, through each camera, and
empties `Draw` at the start of the next frame. Colors are 0xRRGGBB, with `alpha` from 0 to 1.

```haxe
@:system(Update)
static function draw(draw:ResMut<Draw>) {
	draw.rect(10, 10, 120, 40, 0x3366CC, 1, 8);            // rounded corners
	draw.rect(10, 60, 120, 40, 0xFFFFFF, 1, 0, 2, 0x000000); // a 2-pixel border
	draw.circle(200, 30, 20, 0xFFCC00);
	draw.sprite(hero, 160, 60, 32, 32, 0xFFFFFF, 1, angle);
}
```

| Method | Effect |
|---|---|
| `rect(x, y, width, height, color, alpha, radius, border, borderColor, borderAlpha)` | Adds a rectangle, with rounded corners when `radius` is above 0 and a border when `border` is above 0. |
| `circle(x, y, radius, color, alpha, border, borderColor, borderAlpha)` | Adds a circle around `x`, `y`. |
| `ellipse(x, y, width, height, color, alpha)` | Adds an ellipse that fills the rectangle. |
| `line(x0, y0, x1, y1, width, color, alpha, endWidth)` | Adds a line with round ends, `width` wide at its start and `endWidth` wide at its end. |
| `stroke(points, width, color, alpha, widths)` | Adds lines through the x, y pairs of `points`, with the width at each point from `widths`, such as a pen's pressure. |
| `sprite(texture, x, y, width, height, color, alpha, angle, u0, v0, u1, v1)` | Adds the texture stretched over the rectangle and multiplied by the color, turned by `angle` about its center. `u0` to `v1` select part of the texture. |

## Planes

`draw.plane` sets the plane that what is added next lies on, and null puts
it back on the world's XY plane. Each `Plane` moves, turns and scales its
own XY plane into the world: `x`, `y`, `z`, a quaternion `rx`, `ry`, `rz`,
`rw` (or `rotate(angle, ax, ay, az)`), and `scale`. Drawing tools can keep
strokes on planes anywhere in 3D, and a perspective camera that turns
around them shows them in perspective. With `camera.depth`, nearer content
hides farther content whatever order it is drawn in, so planes that
intersect cover each other correctly. Content on one plane still draws in
order:

```haxe
var wall = new Plane();
wall.rotate(Math.PI / 2, 1, 0, 0);   // stand the plane up
wall.z = -100;

draw.plane = wall;
draw.stroke(points, 3, 0x202020, 1, pressures);
draw.plane = null;
```

## Textures

`Texture` holds an image that sprites draw. Make it from RGBA pixels,
with rows top first, at any time: `new Texture(width, height, pixels)`.
The renderer uploads it once the GPU is ready.

The renderer draws each run of sprites that share a texture, and the shapes
between them, with one instanced draw. Each change of texture starts a new
draw.

## Checks

In `tests/draw`, run `hxn check hl cpp cppia app.hxml --vm ash`. The check
draws through a screen camera, an orthographic camera, a perspective camera
and a perspective camera tilted back 45 degrees, each into a render target.
It compares pixels of each shape with the colors it expects, and checks that
the tilted camera sees the far side of a square narrower than its near side.
