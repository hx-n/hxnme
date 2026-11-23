---
name: hxnme-2d
description: Draw sprites and shapes in an hxnme app with the hxnme-2d haxelib (package `hxn.me.render2d`), the 2D renderer of the hxn media engine, through hxnme-gpu on HashLink, Ash, hxcpp and CPPIA. Use when an app draws 2D shapes, sprites or textures, moves a 2D camera, or draws 2D into a render target, or when changing the renderer itself.
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
draw.rect(x, y, w, h, 0x3366CC, 1, radius, border, borderColor);
draw.circle(cx, cy, r, 0xFFCC00);
draw.ellipse(x, y, w, h, color);
draw.line(x0, y0, x1, y1, width, color, alpha, endWidth);
draw.stroke(points /* x, y pairs */, width, color, alpha, widths);
draw.plane = plane;   // hxn.me.render2d.Plane: x, y, z, rx..rw or rotate(), scale; null is the XY plane
draw.sprite(texture, x, y, w, h, tint, alpha, angle, u0, v0, u1, v1);
```

`new Texture(width, height, rgbaPixels)` at any time; it uploads once the
GPU is ready. `Texture.solid(color)` is a one-pixel texture.

Rules:

- Order is draw order. Sprites with the same texture, and shapes between
  them, share one instanced draw; a texture change starts another.
- Shapes are signed distance functions in `Shader`, so they stay smooth
  at any zoom and angle.

## Checks

```
cd tests/draw && hxn check hl cpp cppia app.hxml --vm ash
```

Follow the [hxnme agent rules](https://github.com/hx-n/hxnme/blob/main/AGENTS.md),
the [kernel skill](https://github.com/hx-n/hxnme/blob/main/skills/hxnme/SKILL.md)
and the [hxnme-gpu skill](https://github.com/hx-n/hxnme/blob/main/skills/hxnme-gpu/SKILL.md).
