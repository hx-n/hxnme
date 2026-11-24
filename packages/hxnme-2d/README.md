# hxnme-2d

hxnme-2d is the 2D renderer for [hxnme](../hxnme) apps. It draws sprites,
shapes, nine-slices and text on the GPU with one instanced shader, as a pass
in the frame graph of [hxnme-gpu](../hxnme-gpu). Its API is in the package
`hxn.me.render2d`.

Shapes get their edges from signed distance functions, which give the
distance from each pixel to the edge of the shape. The edges stay smooth at
any size, zoom and angle. Rectangles can have round, squircle, beveled,
scooped or notched corners, as with CSS `corner-shape`.

List the plugin after the window and GPU plugins in the app's `hxnme.toml`:

```toml
plugins = ["hxnme-window", "hxnme-gpu", "hxnme-2d"]
```

## Coordinates

The renderer draws through the cameras of `hxnme-gpu`, which 3D also uses.
The [hxnme-gpu README](../hxnme-gpu) describes how to add and move them.
The world has y up, as in `hxnme-physics`. 2D content lies in the XY plane
of the world, so sprites and physics bodies use the same coordinates.

The main camera is orthographic. It shows one world unit for each logical
pixel, and it is centered on its `x` and `y`. Cameras with the `Screen`
projection show logical pixels, with the origin at the top left and y down.
Use them for UI and HUDs.

For rectangles, ellipses, sprites, nine-slices and text, `x`, `y` is the
corner with the smaller coordinates. In the world, that is the bottom-left
corner. Through a screen camera, it is the top-left corner. Through both
kinds of camera, images show their top row at the top, and text is not
mirrored.

`draw.layer` sets the layer bits of the content that you add next. The
default is 1. Each camera draws only the layers whose bits are set in its
`layers`, which is also 1 by default. For example, the main camera can show
layer 1, and a screen camera that draws after it can show layer 2 for the
UI:

```haxe
draw.layer = 1;
draw.sprite(heroTexture, heroX, heroY, 32, 32);
draw.layer = 2;
draw.rect(16, 16, 200, 24, 0x202020, 0.8, 6);   // a bar in the UI
```

## Drawing

Systems draw through the resource `Draw`. The renderer draws what they
add, in the order that they add it, through each camera. It empties `Draw`
at the start of the next frame, so systems add their content again in each
frame. `draw.layer` and `draw.plane` keep their values from one frame to
the next.

Colors are 0xRRGGBB, with `alpha` from 0 to 1. Angles are in radians.
Texture coordinates `u0`, `v0`, `u1`, `v1` are from 0 to 1, with `v0` at
the top of the texture.

```haxe
@:system(Update)
static function draw(draw:ResMut<Draw>) {
	draw.rect(10, 10, 120, 40, 0x3366CC, 1, 8);            // rounded corners
	draw.rect(10, 60, 120, 40, 0xFFFFFF, 1, 0, 2, 0x000000); // a 2-pixel border
	draw.rect(10, 110, 120, 40, 0x3366CC, 1, 16, 0, 0, 1, Squircle);
	draw.circle(200, 30, 20, 0xFFCC00);
	draw.sprite(heroTexture, 160, 60, 32, 32, 0xFFFFFF, 1, angle);
}
```

| Method | Effect |
|---|---|
| `rect(x, y, width, height, color, alpha, radius, border, borderColor, borderAlpha, corner)` | Adds a rectangle. `radius` is the radius of its corners, and `corner` is their `CornerShape`: `Round` (the default), `Squircle`, `Bevel`, `Scoop`, `Square` or `Notch`. If `border` is above 0, the rectangle has a border. |
| `shadow(x, y, width, height, blur, color, alpha, radius, corner)` | Adds the shadow of a rectangle, blurred by `blur` as with CSS `box-shadow`. Add it before the shape that casts it, at the shadow's offset. The shadow is one instance, and the shader computes its blur for each pixel. |
| `circle(x, y, radius, color, alpha, border, borderColor, borderAlpha)` | Adds a circle with its center at `x`, `y`. |
| `ellipse(x, y, width, height, color, alpha)` | Adds an ellipse that fills the rectangle. |
| `line(x0, y0, x1, y1, width, color, alpha, endWidth)` | Adds a line with round ends. It is `width` wide at its start and `endWidth` wide at its end. `endWidth` defaults to `width`. |
| `stroke(points, width, color, alpha, widths)` | Adds lines through `points`, an array of x, y pairs. `widths` gives the width at each point, for example from the pressure of a pen. Without `widths`, the stroke is `width` wide. |
| `sprite(texture, x, y, width, height, color, alpha, angle, u0, v0, u1, v1)` | Adds the texture stretched over the rectangle and multiplied by the color. `angle` turns it about its center. `u0` to `v1` select part of the texture. |
| `nineSlice(texture, x, y, width, height, left, top, right, bottom, color, alpha, angle, scale)` | Adds the texture as a nine-slice, for panels and buttons. The corners keep their size, the edges stretch along their length, and the center stretches in both directions. `left` to `bottom` are the borders in texture pixels. Each texture pixel covers `scale` logical pixels. If the rectangle is smaller than its borders, the borders shrink to fit. |
| `text(text, x, y, color, alpha, angle)` | Adds a `Text`. See [Text](#text). |
| `region(region, x, y, width, height, color, alpha, angle)` | Adds a region of an atlas, at its own size unless `width` and `height` are given. See [Assets](#assets). |
| `regionSlice(region, x, y, width, height, color, alpha, angle, scale)` | Adds a region of an atlas as a nine-slice with the region's borders. |

Each nine-slice costs the same as one sprite, because the shader does the
slicing on the GPU.

## Clips

`draw.clip` sets the clip of the content that you add next, and null
removes it. Each `Clip` is a rectangle with a corner radius and a
`CornerShape`, in the coordinates of the plane that the content lies on.
Only the parts of the content inside the clip show. The GPU tests each
pixel against the clip, so a clip adds no data to the instances. Changes to
a clip's fields apply from the next frame, so a clip can move with a
scrolling panel.

```haxe
static final panel = new Clip(16, 16, 200, 120, 8);

draw.clip = panel;
draw.text(log, 20, 20 - scroll, 0xFFFFFF);
draw.clip = null;
```

`sprites.clip` sets the clip of the sprites that you add next, in the same
way.

## Text

The resource `Typesetter` lays out text with
[hxn-text](https://github.com/hx-n/hxn-text). It also keeps the
glyph atlases, which are the textures that hold the rasterized glyphs.
`typesetter.text(font, value, options)` returns a `Text`, and
`draw.text(text, x, y, color, alpha, angle)` adds it to the frame. The font
is an `hxn.text.Font`. The options are the `TextOptions` of hxn-text, for
example `{size: 24}` or `{size: 14, maxWidth: 200}`.

```haxe
static var score:Text;

@:system(Start)
static function setup(typesetter:ResMut<Typesetter>) {
	var font = new Font(haxe.Resource.getBytes("ui-font"), {});
	score = typesetter.text(font, "Score 0", {size: 24});
}

@:system(Update)
static function hud(draw:ResMut<Draw>, game:Res<Game>) {
	score.set('Score ${game.score}');
	draw.layer = 2;
	draw.text(score, 16, 16, 0xFFFFFF);
}
```

`x`, `y` is the corner of the text's box with the smaller coordinates, as
for rectangles. `angle` turns the text about the center of its box.
`text.width` and `text.height` give the size of the box in logical pixels.

The first time that a `Text` is drawn or measured, it lays itself out. After
`set` changes its string, or after the display's scale changes, it lays
itself out again. Glyphs are rasterized at the display's scale, so they stay
sharp through a camera that shows one world unit for each logical pixel.
Color glyphs, such as emoji, keep their own colors. They ignore `color`
and use only `alpha`.

## Sprites

The resource `Sprites` keeps sprites from frame to frame, for example the
tiles and characters of a scene. `add` returns a handle to the new sprite,
and the other methods take that handle. The renderer keeps three sets of
buffers and writes one set in each frame, so it never waits for the GPU to
finish with a buffer. It uploads only what changed since it last wrote that
set, so each change is uploaded in each of the next three frames. Sprites
that do not change cost no upload.

```haxe
static var hero:Sprite;

@:system(Start)
static function setup(sprites:ResMut<Sprites>) {
	hero = sprites.add(heroTexture, 160, 60, 32, 32);
}

@:system(Update)
static function walk(sprites:ResMut<Sprites>, time:Res<Time>) {
	sprites.move(hero, sprites.xOf(hero) + 60 * time.delta, sprites.yOf(hero));
}
```

| Method | Effect |
|---|---|
| `add(texture, x, y, width, height, color, alpha, angle, u0, v0, u1, v1)` | Adds a sprite with the arguments of `draw.sprite`, and returns its handle. |
| `remove(sprite)` | Removes the sprite and makes its handle invalid. Later sprites can reuse its storage, but the old handle never becomes valid again. |
| `exists(sprite)` | Returns whether the handle refers to a sprite in `Sprites`. |
| `move(sprite, x, y)`, `resize(sprite, width, height)` | Set the sprite's corner and size. |
| `turn(sprite, angle)` | Turns the sprite to `angle` radians about its center. |
| `tint(sprite, color, alpha)` | Sets the color and alpha that multiply the texture. |
| `region(sprite, u0, v0, u1, v1)` | Selects the part of the texture that the sprite shows. |
| `xOf(sprite)`, `yOf(sprite)` | Return the sprite's corner. |
| `addRegion(region, x, y, width, height, color, alpha, angle)` | Adds a region of an atlas as a sprite, at its own size unless `width` and `height` are given. |
| `addText(text, x, y, color, alpha, angle)` | Adds a `Text` and returns its handle, which `move`, `turn`, `tint`, `xOf`, `yOf`, `exists` and `remove` take. |

Text in `Sprites` keeps its glyph instances from frame to frame. The
renderer writes and uploads them again only after the text moves, turns or
changes color, or lays itself out again. Each text draws with one instanced
draw for each glyph atlas that it uses. Use `addText` for labels that change
less often than every frame, and `draw.text` for text that changes in each
frame.

`sprites.layer`, `sprites.plane` and `sprites.clip` set the layer, the plane
and the clip of the sprites that you add next, as in `Draw`. Sprites with
the same texture, layer, plane and clip form a group, and each group draws with one instanced draw.
Groups draw in the order that their first sprites were added, and before
the contents of `Draw`. The sprites of one group draw in the order that
they were added. `remove` changes that order, because it moves the last
sprite of the group into the place of the removed sprite.

## Planes

Each `Plane` is a surface for 2D content anywhere in the 3D world. Content
drawn on a plane lies in the plane's own XY plane. The plane maps that
content into the world in three steps:

1. It scales the content by `scale`.
2. It turns the content by the quaternion `rx`, `ry`, `rz`, `rw`. `rotate(angle, ax, ay, az)` sets the quaternion from an angle in radians and an axis of length 1.
3. It moves the content to `x`, `y`, `z`.

`draw.plane` sets the plane of the content that you add next. Set it to
null to go back to the XY plane of the world. For example, a drawing app
can keep strokes on planes at any angle, and a perspective camera shows
them in perspective.

`camera.depth` is false by default, and content then draws in the order
that it was added. When `camera.depth` is true, nearer content hides
farther content in any draw order, so planes that intersect cover each
other correctly. Content on one plane draws in the order that it was added
in both cases.

```haxe
var ground = new Plane();
ground.rotate(Math.PI / 2, 1, 0, 0);   // lay the plane flat, in the XZ plane
ground.y = -100;

draw.plane = ground;
draw.stroke(points, 3, 0x202020, 1, pressures);
draw.plane = null;
```

## Assets

`hxn.me.render2d.RenderAssets` holds the asset types of the renderer, for
the kernel's `hxn.me.Assets`:

| Type | Loads |
|---|---|
| `RenderAssets.texture` | A PNG image as a `Texture`. When the asset is released, the texture draws nothing more, and its GPU texture is released at the start of the next frame, so what was drawn with it earlier in the frame still shows. |
| `RenderAssets.font` | A TTF, OpenType or WOFF2 file as an `hxn.text.Font`, for `typesetter.text`. |
| `RenderAssets.atlas` | A JSON file of named regions, and the image it lists, as an `Atlas`. |

```haxe
assets.load("ui/sheet.json", RenderAssets.atlas).then(a -> sheet = a);

var atlas = sheet.value;
draw.region(atlas.region("hero"), x, y);
draw.regionSlice(atlas.region("panel"), 16, 16, 200, 80, 0xFFFFFF, 1, 0, 2);
sprites.addRegion(atlas.region("tree"), 120, 40);
```

The atlas file lists the image, relative to the file, and each region's
corner and size in texture pixels, top left first. `slice` gives a region's
nine-slice borders, left, top, right and bottom:

```json
{
	"image": "sheet.png",
	"regions": {
		"hero": {"x": 0, "y": 0, "width": 16, "height": 16},
		"panel": {"x": 17, "y": 0, "width": 12, "height": 12, "slice": [4, 4, 4, 4]}
	}
}
```

Leave at least one pixel between regions, because linear filtering reads the
texels next to a region at its edges. The atlas holds its texture, and
releasing the atlas closes it.

## Textures

`Texture` holds an image that sprites draw. Make it from `haxe.io.Bytes`
of RGBA pixels, 4 bytes for each pixel, with the top row first:
`new Texture(width, height, pixels)`. You can make it at any time. If you
make it before the GPU device opens, the renderer uploads it in the first
frame after the device opens. Textures are sampled with linear filtering.

In `Draw`, sprites that share a texture, and the shapes between them,
draw with one draw call. Each change of texture starts a new draw call. To
keep draw calls few, add sprites with the same texture one after another,
or pack their images into one texture.

## Checks

In `tests/draw` of this package, run
`hxn check hl cpp cppia app.hxml --vm ash`. The check runs the test app on
HashLink through Ash, on hxcpp and on CPPIA. It draws into one off-screen
render target for each of these cameras:

- Screen camera.
- Orthographic camera.
- Perspective camera.
- Perspective camera tilted back 45 degrees.
- Orthographic camera with depth.
- Screen camera that shows `Sprites`.
- Screen camera and orthographic camera that show the same text and nine-slice.
- Screen camera that shows text in `Sprites`.

The check compares one pixel of each shape with the color that it expects.
It also tests that:

- The tilted camera shows the far side of a square as narrower than its near side.
- A pixel near the corner of a squircle is inside it, and the same pixel near a round corner is outside.
- A rectangle in a clip with rounded corners shows only inside the clip.
- The middle of a shadow is fully covered, and the blur covers its edge in part.
- After one sprite moves and another is removed, each of the next three frames uploads only the changed parts. Later frames upload nothing.
- The text changes from L to T after the first frame. The two text cameras show a T with its bar at the top, so the text was laid out again and is not mirrored. The top border of the nine-slice is at the top.
- Text in `Sprites` that changes from L to T also shows a T, and uploads only its one new glyph.

In `tests/assets`, the same command runs the asset check. It loads an atlas
and a font through `Assets`, draws a region and a nine-slice region, and
tests their pixels, the font's layout, and that releasing the atlas closes
its texture.

The checks use the font Noto Sans. Its license is listed in
[third-party/NOTICES.md](third-party/NOTICES.md).
