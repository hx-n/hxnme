import haxe.io.Bytes;
import hxn.me.Lifecycle;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.gpu.Camera;
import hxn.me.gpu.Cameras;
import hxn.me.gpu.Gpu;
import hxn.me.gpu.RenderTarget;
import hxn.me.render2d.Draw;
import hxn.me.render2d.Plane;
import hxn.me.render2d.Texture;

/**
	The check draws through two cameras, each into a 64x64 render target. The
	main camera is a screen camera that shows layer 1: shapes, a sprite, and
	an image whose top half is red and bottom half blue. The second camera is
	an orthographic camera in the world, with y up, that shows layer 2: a
	yellow square at the world's origin, the same image, a green line, a cyan
	line that widens from its start to its end, and a magenta rectangle on a
	plane that is turned 90 degrees and moved. The third is a
	perspective camera with a 90-degree field of view, 32 units in front of
	the z = 0 plane, so it sees the same 64 by 64 units as the second and its
	target matches the second's. The fourth is a perspective camera tilted
	back 45 degrees about x, which sees a white square in the XY plane with its
	far side narrower than its near side. After the plugin
	presents three frames, the check reads both targets back, compares one
	pixel of each shape with the color it expects, and stops the app.
**/
class Scene {
	static final screen = new RenderTarget(64, 64);
	static final world = new RenderTarget(64, 64);
	static final perspective = new RenderTarget(64, 64);
	static final tilted = new RenderTarget(128, 128);
	static var image:Texture;
	static var halves:Texture;
	static var reading = false;
	static final turned = new Plane();

	// Rows of the readback are top first, as each target shows them.
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
		{target: perspective, name: "bottom of the image through the perspective camera", x: 44, y: 22, rgb: [0, 0, 255]}
	];

	@:system(Start)
	static function setup(cameras:ResMut<Cameras>) {
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
		turned.rotate(Math.PI / 2, 0, 0, 1);
		turned.x = 20;
		turned.y = 40;
		image = new Texture(2, 2, pixels([40, 80, 120], [40, 80, 120]));
		halves = new Texture(1, 2, pixels([255, 0, 0], [0, 0, 255], 1));
	}

	// Rows of `width` pixels: the first half of the rows in `top`, the rest in `bottom`.
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
	}

	// Returns how many pixels of row `y` in a `size`-wide readback are white.
	static function width(pixels:Bytes, size:Int, y:Int):Int {
		var n = 0;
		for (x in 0...size)
			if (pixels.get((y * size + x) * 4) > 128)
				n++;
		return n;
	}

	@:system(Update)
	static function check(gpu:Res<Gpu>, lifecycle:ResMut<Lifecycle>) {
		if (gpu.failure != null) {
			Sys.println('no GPU: ${gpu.failure}');
			lifecycle.quit();
			return;
		}
		if (gpu.presented < 3 || reading)
			return;
		reading = true;
		var state:Lifecycle = lifecycle;
		var device = gpu.device;
		device.readTexture(screen.texture).then(onScreen -> device.readTexture(world.texture).then(inWorld -> device.readTexture(perspective.texture).then(seen -> device.readTexture(tilted.texture).then(tilt -> {
			var failed = 0;
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
			for (e in expected) {
				var pixels = e.target == screen ? onScreen : e.target == world ? inWorld : seen;
				var at = (e.y * 64 + e.x) * 4;
				var got = [for (c in 0...3) pixels.get(at + c)];
				var close = [for (c in 0...3) Math.abs(got[c] - e.rgb[c]) <= 2].indexOf(false) < 0;
				if (!close)
					failed++;
				Sys.println('${e.name}: ${close ? "as expected" : 'got ${got.join(", ")}, not ${e.rgb.join(", ")}'}');
			}
			if (failed > 0) {
				Sys.println('$failed pixels differ');
				Sys.exit(1);
			}
			state.quit();
		}, failure), failure), failure), failure);
	}

	static function failure(e:haxe.Exception) {
		Sys.println('readback failed: ${e.message}');
		Sys.exit(1);
	}
}
