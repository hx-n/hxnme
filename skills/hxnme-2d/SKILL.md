---
name: hxnme-2d
description: Draw sprites, shapes (with round, squircle and other corner shapes), shadows, nine-slices and text, clip them, and keep sprites from frame to frame, in an hxnme app with the hxnme-2d haxelib (package `hxn.me.render2d`), the 2D renderer of the hxn media engine, through hxnme-gpu on HashLink, Ash, hxcpp and CPPIA. Use when an app draws 2D shapes, sprites or textures, moves a 2D camera, or draws 2D into a render target, or when changing the renderer itself.
---

# hxnme-2d

## Setup

```toml
plugins = ["hxnme-window", "hxnme-gpu", "hxnme-2d"]
```

## Use

The renderer draws through `hxn.me.gpu.Cameras` (see the hxnme-gpu skill),
shared with 3D. The world has y up, as in physics; 2D lies in the XY plane.
The main camera is orthographic, one unit per logical pixel. `Screen`
cameras show logical pixels, top left, y down, for UI. Each shape's `x`, `y`
is its corner with the smaller coordinates. `draw.layer` sets the layer bits of
what is added next; each camera draws the layers in its `layers`.

Draw through `ResMut<Draw>` in `Update`, every frame; it is emptied in
`Begin`. Colors are 0xRRGGBB with `alpha` 0 to 1.

```haxe
draw.rect(x, y, w, h, 0x3366CC, 1, radius, border, borderColor, borderAlpha, Squircle /* CornerShape */);
draw.circle(cx, cy, r, 0xFFCC00);
draw.shadow(x + 4, y + 4, w, h, blur, 0x000000, 0.5, radius, corner);   // before the shape
draw.clip = new Clip(x, y, w, h, radius, corner);   // null removes it; plane coordinates
draw.ellipse(x, y, w, h, color);
draw.line(x0, y0, x1, y1, width, color, alpha, endWidth);
draw.stroke(points /* x, y pairs */, width, color, alpha, widths);
draw.plane = plane;   // hxn.me.render2d.Plane: x, y, z, rx..rw or rotate(), scale; null is the XY plane
// camera.depth = true: nearer planes hide farther ones in any order; one plane still draws in order
draw.sprite(texture, x, y, w, h, tint, alpha, angle, u0, v0, u1, v1);
draw.nineSlice(texture, x, y, w, h, left, top, right, bottom /* texture px */, tint, alpha, angle, scale);
```

Sprites that stay from frame to frame go in `ResMut<Sprites>`. Only the
parts that change are uploaded, so sprites that stand still cost nothing:

```haxe
sprites.layer = 1; sprites.plane = null; sprites.clip = null;   // for the sprites added next
var s:Sprite = sprites.add(texture, x, y, w, h, tint, alpha, angle, u0, v0, u1, v1);
sprites.move(s, x, y); sprites.resize(s, w, h); sprites.turn(s, angle);
sprites.tint(s, color, alpha); sprites.region(s, u0, v0, u1, v1);
sprites.xOf(s); sprites.yOf(s); sprites.exists(s); sprites.remove(s);
var t:Sprite = sprites.addText(label, x, y, color, alpha, angle);   // glyphs kept; move, turn, tint, remove
```

Text goes through `ResMut<Typesetter>` (hxn-text). Keep the `Text` and
`set` its string; it lays itself out again only when the string, the
display's scale or the atlases change:

```haxe
var label:Text = typesetter.text(font /* hxn.text.Font */, "Score 0", {size: 24});
label.set("Score 10"); label.width; label.height;
draw.text(label, x, y, color, alpha, angle);   // upright through y-up and Screen cameras
```

Assets through the kernel's `ResMut<Assets>`, with `RenderAssets.texture`
(PNG), `RenderAssets.font` (TTF, OTF, WOFF2) and `RenderAssets.atlas` (JSON
of regions with an image; `slice: [l, t, r, b]` for nine-slices):

```haxe
assets.load("ui/sheet.json", RenderAssets.atlas).then(a -> sheet = a);   // sheet.release() closes it
draw.region(sheet.value.region("hero"), x, y);
draw.regionSlice(sheet.value.region("panel"), x, y, w, h, tint, alpha, angle, scale);
sprites.addRegion(sheet.value.region("tree"), x, y);
```

`new Texture(width, height, rgbaPixels)` at any time; it uploads once the
GPU is ready. `Texture.solid(color)` is a one-pixel texture.

Rules:

- Order is draw order. Sprites with the same texture, and shapes between
  them, share one instanced draw; a texture change starts another.
- Clips are uniforms of each run and group, tested for each pixel in the
  shader. A clip change starts a new run.
- `Sprites` groups sprites by texture, layer, plane and clip, with one draw for
  each group. Groups draw before `Draw`, in the order of their first
  sprites. `remove` moves the group's last sprite into the removed one's
  place, which changes the order within the group.
- Glyphs sample hxn-text's coverage atlas, rasterized at the display's
  scale, in the same shader. Text shares runs with sprites on the atlas
  texture.
- Shapes are signed distance functions in `Sdf`, so they stay smooth at
  any zoom and angle. `Sdf.shapedBox` takes a radius and a `CornerShape`
  for each corner. The UI imports the same module.
- Each nine-slice is one instance. `Slice` fits the borders and maps the
  pieces on the GPU.
- `Shader` keeps only the vertex and fragment stages. Put new shader
  functions in a module of functions that `Shader` brings in with hxnsl's
  `@:import`, as `Sdf` and `Slice` are.

## Checks

```
cd tests/draw && hxn check hl cpp cppia app.hxml --vm ash
```

Follow the [hxnme agent rules](https://github.com/hx-n/hxnme/blob/main/AGENTS.md),
the [kernel skill](https://github.com/hx-n/hxnme/blob/main/skills/hxnme/SKILL.md)
and the [hxnme-gpu skill](https://github.com/hx-n/hxnme/blob/main/skills/hxnme-gpu/SKILL.md).
