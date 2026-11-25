import haxe.io.Bytes;
import hxn.me.Lifecycle;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.gpu.Camera;
import hxn.me.gpu.Cameras;
import hxn.me.gpu.Gpu;
import hxn.me.gpu.RenderTarget;
import hxn.me.render2d.Clip;
import hxn.me.render2d.Draw;
import hxn.me.render2d.Plane;
import hxn.me.render2d.Sprite;
import hxn.me.render2d.Sprites;
import hxn.me.render2d.Text;
import hxn.me.render2d.Texture;
import hxn.me.render2d.Typesetter;
import hxn.text.Font;

/**
	`Scene` runs the 2D check. It draws through nine cameras, each into its
	own render target. After the renderer fills each of its sets of buffers,
	it changes part of what it draws. After a few more frames, it reads every
	target back and compares it with what each camera must show. The Checks
	section of the README lists what it tests.
**/
class Scene {
	static final screen = new RenderTarget(64, 64);
	static final world = new RenderTarget(64, 64);
	static final perspective = new RenderTarget(64, 64);
	static final tilted = new RenderTarget(128, 128);
	static final deep = new RenderTarget(64, 64);
	static final kept = new RenderTarget(64, 64);
	static var moved:Sprite;
	static var removed:Sprite;
	static var changed = false;
	// Sets the frame in which the check changes what it draws, after the renderer filled each set of buffers.
	static inline final CHANGE = hxn.me.render2d.Renderer.SETS;
	// Holds what `Sprites` uploaded in each frame after the change.
	static final uploadsAfterChange:Array<Int> = [];
	static final lettered = new RenderTarget(64, 64);
	static final letteredUp = new RenderTarget(64, 64);
	static final retained = new RenderTarget(64, 64);
	static var keptLabel:Text;
	static var label:Text;
	static var panel:Texture;
	static final near = new Plane();
	static var image:Texture;
	static var halves:Texture;
	static var reading = false;
	static final turned = new Plane();
	static final clip = new Clip(12, 38, 16, 20, 6);

	// The rows of the readback are top first, as each target shows them.
	static final expected = [
		{target: screen, name: "rectangle", x: 8, y: 8, rgb: [255, 0, 0]},
		{target: screen, name: "circle", x: 48, y: 16, rgb: [0, 255, 0]},
		{target: screen, name: "outside the circle", x: 38, y: 5, rgb: [0, 0, 0]},
		{target: screen, name: "rounded rectangle", x: 12, y: 52, rgb: [0, 0, 255]},
		{target: screen, name: "rounded corner", x: 1, y: 41, rgb: [0, 0, 0]},
		{target: screen, name: "border", x: 34, y: 52, rgb: [255, 0, 255]},
		{target: screen, name: "inside the border", x: 44, y: 52, rgb: [255, 255, 255]},
		{target: screen, name: "sprite", x: 4, y: 36, rgb: [40, 80, 120]},
		{target: screen, name: "top of the image on the screen", x: 60, y: 57, rgb: [255, 0, 0]},
		{target: screen, name: "bottom of the image on the screen", x: 60, y: 62, rgb: [0, 0, 255]},
		{target: world, name: "square at the world's origin", x: 8, y: 56, rgb: [255, 255, 0]},
		{target: world, name: "above the square", x: 8, y: 8, rgb: [0, 0, 0]},
		{target: world, name: "top of the image in the world", x: 44, y: 17, rgb: [255, 0, 0]},
		{target: world, name: "bottom of the image in the world", x: 44, y: 22, rgb: [0, 0, 255]},
		{target: world, name: "line", x: 48, y: 60, rgb: [0, 255, 0]},
		{target: world, name: "above the line", x: 48, y: 56, rgb: [0, 0, 0]},
		{target: world, name: "thin start of the widening line", x: 42, y: 41, rgb: [0, 0, 0]},
		{target: world, name: "wide end of the widening line", x: 58, y: 41, rgb: [0, 255, 255]},
		{target: world, name: "rectangle on the turned plane", x: 18, y: 19, rgb: [255, 0, 255]},
		{target: world, name: "beside the turned plane's rectangle", x: 22, y: 19, rgb: [0, 0, 0]},
		{target: perspective, name: "square through the perspective camera", x: 8, y: 56, rgb: [255, 255, 0]},
		{target: perspective, name: "above the square through the perspective camera", x: 8, y: 8, rgb: [0, 0, 0]},
		{target: perspective, name: "top of the image through the perspective camera", x: 44, y: 17, rgb: [255, 0, 0]},
		{target: perspective, name: "bottom of the image through the perspective camera", x: 44, y: 22, rgb: [0, 0, 255]},
		{target: deep, name: "nearer square drawn first, through the camera with depth", x: 32, y: 32, rgb: [255, 0, 0]},
		{target: kept, name: "where the moved sprite was", x: 4, y: 4, rgb: [0, 0, 0]},
		{target: kept, name: "moved sprite", x: 36, y: 36, rgb: [0, 255, 0]},
		{target: kept, name: "where the removed sprite was", x: 20, y: 4, rgb: [0, 0, 0]},
		{target: kept, name: "sprite that took the removed sprite's place", x: 52, y: 4, rgb: [0, 0, 255]},
		{target: kept, name: "sprite of a second texture", x: 4, y: 52, rgb: [40, 80, 120]},
		{target: kept, name: "near the corner of the squircle", x: 12, y: 12, rgb: [255, 255, 255]},
		{target: kept, name: "same place near a round corner", x: 36, y: 12, rgb: [0, 0, 0]},
		{target: kept, name: "inside the clip", x: 20, y: 48, rgb: [255, 0, 0]},
		{target: kept, name: "outside the clip", x: 11, y: 48, rgb: [0, 0, 0]},
		{target: kept, name: "in the clip's rounded corner", x: 12, y: 38, rgb: [0, 0, 0]},
		{target: kept, name: "middle of the shadow", x: 52, y: 52, rgb: [255, 255, 255]},
		{target: lettered, name: "nine-slice corner on the screen", x: 38, y: 8, rgb: [255, 0, 0]},
		{target: lettered, name: "nine-slice top edge on the screen", x: 48, y: 8, rgb: [0, 255, 0]},
		{target: lettered, name: "nine-slice side on the screen", x: 38, y: 24, rgb: [0, 255, 255]},
		{target: lettered, name: "nine-slice center on the screen", x: 48, y: 24, rgb: [0, 0, 255]},
		{target: lettered, name: "nine-slice bottom edge on the screen", x: 48, y: 40, rgb: [255, 255, 0]},
		{target: letteredUp, name: "nine-slice corner with y up", x: 38, y: 24, rgb: [255, 0, 0]},
		{target: letteredUp, name: "nine-slice top edge with y up", x: 48, y: 24, rgb: [0, 255, 0]},
		{target: letteredUp, name: "nine-slice side with y up", x: 38, y: 40, rgb: [0, 255, 255]},
		{target: letteredUp, name: "nine-slice center with y up", x: 48, y: 40, rgb: [0, 0, 255]},
		{target: letteredUp, name: "nine-slice bottom edge with y up", x: 48, y: 56, rgb: [255, 255, 0]}
	];

	// Moving the first sprite writes its rect, and the sprite that fills the
	// removed one's place writes all seven fields. The upload holds the rects of
	// indices 0 and 1, and one instance of each other field. The text in
	// `Sprites` changes from L to T, which uploads one glyph of all the fields.
	static final CHANGED_BYTES = 2 * 16 + (hxn.me.render2d.Instances.BYTES - 16) + hxn.me.render2d.Instances.BYTES;

	/**
		Sets up one camera for each part of the check, each with its own layers
		and render target:

		- 1, the main camera: a screen camera of shapes and sprites.
		- 2: an orthographic camera with y up, of shapes, an image and lines,
		  and a rectangle on a turned plane.
		- 3: a perspective camera that sees the same 64 by 64 units as camera 2.
		- 4: a perspective camera tilted back 45 degrees, of a square.
		- 5: an orthographic camera with depth, of two squares on two planes.
		- 6: a screen camera of `Sprites`, corner shapes, a clip and a shadow.
		- 7 and 8: a screen camera and a camera with y up, of text and a
		  nine-slice.
		- 9: a screen camera of text in `Sprites`.
	**/
	@:system(Start)
	static function setup(cameras:ResMut<Cameras>, sprites:ResMut<Sprites>, typesetter:ResMut<Typesetter>) {
		var main = cameras.main;
		main.projection = Screen;
		main.target = screen;
		main.clear = {r: 0, g: 0, b: 0, a: 1};
		var second = new Camera();
		second.projection = Orthographic(64, -1000, 1000);
		second.x = 32;
		second.y = 32;
		second.layers = 2;
		second.order = 1;
		second.target = world;
		second.clear = {r: 0, g: 0, b: 0, a: 1};
		cameras.add(second);
		var third = new Camera();
		third.projection = Perspective(Math.PI / 2, 1, 1000);
		third.x = 32;
		third.y = 32;
		third.z = 32;
		third.layers = 2;
		third.order = 2;
		third.target = perspective;
		third.clear = {r: 0, g: 0, b: 0, a: 1};
		cameras.add(third);
		var fourth = new Camera();
		fourth.projection = Perspective(Math.PI / 3, 1, 1000);
		var angle = Math.PI / 4;
		fourth.rx = Math.sin(angle / 2);
		fourth.rw = Math.cos(angle / 2);
		fourth.y = -80 * Math.sin(angle);
		fourth.z = 80 * Math.cos(angle);
		fourth.layers = 4;
		fourth.order = 3;
		fourth.target = tilted;
		fourth.clear = {r: 0, g: 0, b: 0, a: 1};
		cameras.add(fourth);
		var fifth = new Camera();
		fifth.projection = Orthographic(64, -1000, 1000);
		fifth.x = 32;
		fifth.y = 32;
		fifth.layers = 8;
		fifth.order = 4;
		fifth.depth = true;
		fifth.target = deep;
		fifth.clear = {r: 0, g: 0, b: 0, a: 1};
		cameras.add(fifth);
		var sixth = new Camera();
		sixth.projection = Screen;
		sixth.layers = 16;
		sixth.order = 5;
		sixth.target = kept;
		sixth.clear = {r: 0, g: 0, b: 0, a: 1};
		cameras.add(sixth);
		var seventh = new Camera();
		seventh.projection = Screen;
		seventh.layers = 32;
		seventh.order = 6;
		seventh.target = lettered;
		seventh.clear = {r: 0, g: 0, b: 0, a: 1};
		cameras.add(seventh);
		var eighth = new Camera();
		eighth.projection = Orthographic(64, -1000, 1000);
		eighth.x = 32;
		eighth.y = 32;
		eighth.layers = 32;
		eighth.order = 7;
		eighth.target = letteredUp;
		eighth.clear = {r: 0, g: 0, b: 0, a: 1};
		cameras.add(eighth);
		var ninth = new Camera();
		ninth.projection = Screen;
		ninth.layers = 64;
		ninth.order = 8;
		ninth.target = retained;
		ninth.clear = {r: 0, g: 0, b: 0, a: 1};
		cameras.add(ninth);
		// Each region of the panel is 4x4 texels, so linear filtering keeps the middle of each piece one color.
		var regions = [
			[255, 0, 0], [0, 255, 0], [255, 0, 0],
			[0, 255, 255], [0, 0, 255], [0, 255, 255],
			[255, 0, 0], [255, 255, 0], [255, 0, 0]
		];
		var bytes = Bytes.alloc(12 * 12 * 4);
		for (py in 0...12)
			for (px in 0...12) {
				var rgb = regions[Std.int(py / 4) * 3 + Std.int(px / 4)];
				for (c in 0...3)
					bytes.set((py * 12 + px) * 4 + c, rgb[c]);
				bytes.set((py * 12 + px) * 4 + 3, 255);
			}
		panel = new Texture(12, 12, bytes);
		var font = new Font(haxe.Resource.getBytes("font"), {});
		label = (typesetter : Typesetter).text(font, "L", {size: 40});
		keptLabel = (typesetter : Typesetter).text(font, "L", {size: 40});
		near.z = 10;
		turned.rotate(Math.PI / 2, 0, 0, 1);
		turned.x = 20;
		turned.y = 40;
		image = new Texture(2, 2, pixels([40, 80, 120], [40, 80, 120]));
		halves = new Texture(1, 2, pixels([255, 0, 0], [0, 0, 255], 1));
		var store:Sprites = sprites;
		var blank = Texture.solid(0xFFFFFF);
		store.layer = 16;
		// The handle of a removed sprite stays invalid after another sprite takes its slot.
		var gone = store.add(blank, 0, 0, 1, 1);
		store.remove(gone);
		var reused = store.add(blank, 0, 0, 1, 1);
		if (store.exists(gone) || !store.exists(reused))
			fail("a removed sprite's handle is still valid after its slot was reused");
		store.remove(reused);
		moved = store.add(blank, 0, 0, 8, 8, 0x00FF00);
		removed = store.add(blank, 16, 0, 8, 8, 0xFF0000);
		store.add(blank, 48, 0, 8, 8, 0x0000FF);
		store.add(image, 0, 48, 8, 8);
		store.layer = 64;
		store.addText(keptLabel, 8, 4, 0xFFFFFF);
	}

	// In frame `CHANGE`, moves one sprite, removes another and changes both texts. In the frames after it, records what `Sprites` uploaded.
	@:system(Update)
	static function change(gpu:Res<Gpu>, sprites:ResMut<Sprites>) {
		var store:Sprites = sprites;
		if (gpu.presented == CHANGE && !changed) {
			changed = true;
			store.move(moved, 32, 32);
			store.remove(removed);
			label.set("T");
			keptLabel.set("T");
		} else if (changed && uploadsAfterChange.length < hxn.me.render2d.Renderer.SETS)
			uploadsAfterChange.push(store.uploaded);
	}

	static function fail(message:String) {
		Sys.println(message);
		Sys.exit(1);
	}

	// Returns rows of `width` pixels. The first half of the rows are in `top`, and the rest are in `bottom`.
	static function pixels(top:Array<Int>, bottom:Array<Int>, width = 2):Bytes {
		var bytes = Bytes.alloc(width * 2 * 4);
		for (i in 0...width * 2) {
			var rgb = i < width ? top : bottom;
			for (c in 0...3)
				bytes.set(i * 4 + c, rgb[c]);
			bytes.set(i * 4 + 3, 255);
		}
		return bytes;
	}

	@:system(Update)
	static function draw(draw:ResMut<Draw>) {
		draw.layer = 1;
		draw.rect(0, 0, 32, 32, 0xFF0000);
		draw.circle(48, 16, 12, 0x00FF00);
		draw.rect(0, 40, 24, 24, 0x0000FF, 1, 8);
		draw.rect(32, 40, 24, 24, 0xFFFFFF, 1, 0, 4, 0xFF00FF);
		draw.sprite(image, 0, 32, 8, 8);
		draw.sprite(halves, 56, 56, 8, 8);
		draw.layer = 2;
		draw.rect(0, 0, 32, 32, 0xFFFF00);
		draw.sprite(halves, 40, 40, 8, 8);
		draw.line(34, 4, 62, 4, 4, 0x00FF00);
		draw.line(40, 20, 60, 20, 2, 0x00FFFF, 1, 10);
		draw.plane = turned;
		draw.rect(0, 0, 10, 4, 0xFF00FF);
		draw.plane = null;
		draw.layer = 4;
		draw.rect(-30, -30, 60, 60, 0xFFFFFF);
		draw.layer = 8;
		draw.plane = near;
		draw.rect(16, 16, 32, 32, 0xFF0000);
		draw.plane = null;
		draw.rect(16, 16, 32, 32, 0x0000FF);
		draw.layer = 16;
		// Squircle corners reach nearer the corner of the box than round ones, along the diagonal.
		draw.rect(10, 10, 20, 20, 0xFFFFFF, 1, 10, 0, 0, 1, Squircle);
		draw.rect(34, 10, 20, 20, 0xFFFFFF, 1, 10);
		draw.clip = clip;
		draw.rect(10, 34, 22, 28, 0xFF0000);
		draw.clip = null;
		draw.shadow(46, 46, 12, 12, 4, 0xFFFFFF, 1);
		draw.layer = 32;
		draw.text(label, 8, 4, 0xFFFFFF);
		draw.nineSlice(panel, 34, 4, 28, 40, 4, 4, 4, 4, 0xFFFFFF, 1, 0, 2);
	}

	// Returns whether the lit pixels in the left half of `pixels`, 64 wide,
	// form a T. The pixels must have some lit rows, and the widest of them must
	// be in the top fifth.
	static function upright(pixels:Bytes):Bool {
		var rows = [for (y in 0...64) width(pixels, 64, y, 32)];
		var first = 0;
		while (first < 64 && rows[first] == 0)
			first++;
		var last = 63;
		while (last > first && rows[last] == 0)
			last--;
		if (first >= last)
			return false;
		var widest = first;
		for (y in first...last + 1)
			if (rows[y] > rows[widest])
				widest = y;
		return widest - first < (last - first + 1) / 5 && rows[widest] > rows[last] * 2;
	}

	// Returns how many of the first `columns` pixels of row `y` in a `size`-wide readback are white.
	static function width(pixels:Bytes, size:Int, y:Int, columns = -1):Int {
		var n = 0;
		for (x in 0...(columns < 0 ? size : columns))
			if (pixels.get((y * size + x) * 4) > 128)
				n++;
		return n;
	}

	@:system(Update)
	static function check(gpu:Res<Gpu>, lifecycle:ResMut<Lifecycle>, sprites:Res<Sprites>) {
		if (gpu.failure != null)
			fail('no GPU: ${gpu.failure}');
		if (gpu.presented < CHANGE + hxn.me.render2d.Renderer.SETS + 2 || reading)
			return;
		reading = true;
		var state:Lifecycle = lifecycle;
		var device = gpu.device;
		var targets = [screen, world, perspective, tilted, deep, kept, lettered, letteredUp, retained];
		var read:Array<Bytes> = [];
		function next() {
			if (read.length < targets.length) {
				device.readTexture(targets[read.length].texture).then(pixels -> {
					read.push(pixels);
					next();
				}, failure);
				return;
			}
			compare(targets, read, sprites, state);
		}
		next();
	}

	static function compare(targets:Array<RenderTarget>, read:Array<Bytes>, sprites:Sprites, state:Lifecycle) {
		var failed = 0;
		var tilt = read[targets.indexOf(tilted)];
		var rows = [for (y in 0...128) width(tilt, 128, y)];
		var first = 0;
		while (first < 128 && rows[first] == 0)
			first++;
		var last = 127;
		while (last > 0 && rows[last] == 0)
			last--;
		var far = rows[first + 2], near = rows[last - 2];
		var foreshortened = first < last && far > 0 && far < near * 0.8;
		if (!foreshortened)
			failed++;
		Sys.println('tilted square: ${foreshortened ? "its far side is narrower than its near side" : 'far side $far pixels, near side $near'}');
		// The blur covers the shadow's edge in part. The expected coverage is about 0.6 at the edge, and about 0.1 at 2.5 pixels outside it.
		var shadowed = read[targets.indexOf(kept)];
		var edge = shadowed.get((52 * 64 + 46) * 4), beyond = shadowed.get((52 * 64 + 43) * 4);
		var blurred = edge > 110 && edge < 200 && beyond > 5 && beyond < 60;
		if (!blurred)
			failed++;
		Sys.println('shadow: ${blurred ? "its edge is blurred" : 'edge $edge, beyond it $beyond'}');
		for (e in expected) {
			var pixels = read[targets.indexOf(e.target)];
			var at = (e.y * 64 + e.x) * 4;
			var got = [for (c in 0...3) pixels.get(at + c)];
			var close = [for (c in 0...3) Math.abs(got[c] - e.rgb[c]) <= 2].indexOf(false) < 0;
			if (!close)
				failed++;
			Sys.println('${e.name}: ${close ? "as expected" : 'got ${got.join(", ")}, not ${e.rgb.join(", ")}'}');
		}
		for (target in [lettered, letteredUp, retained]) {
			var ok = upright(read[targets.indexOf(target)]);
			if (!ok)
				failed++;
			Sys.println('${target == lettered ? "text through the screen camera" : target == letteredUp ? "text through the camera with y up" : "text in Sprites"}: ${ok ? "an upright T" : "not an upright T"}');
		}
		// The change reaches each set of buffers in turn, so each of the frames after it uploads the changed parts.
		var changes = uploadsAfterChange.length == hxn.me.render2d.Renderer.SETS && uploadsAfterChange.filter(b -> b != CHANGED_BYTES).length == 0;
		if (!changes)
			failed++;
		Sys.println('sprite uploads after the change: ${changes ? "only the changed parts, once for each set" : '${uploadsAfterChange.join(", ")} bytes, not $CHANGED_BYTES each'}');
		var still = sprites.uploaded == 0;
		if (!still)
			failed++;
		Sys.println('sprite upload without a change: ${still ? "nothing" : '${sprites.uploaded} bytes'}');
		if (failed > 0)
			fail('$failed checks failed');
		Sys.println("hxnme-2d: " + hxn.me.Plugins.names.join(", "));
		Sys.println("2D checks passed");
		state.quit();
	}

	static function failure(e:haxe.Exception) {
		Sys.println('readback failed: ${e.message}');
		Sys.exit(1);
	}
}
