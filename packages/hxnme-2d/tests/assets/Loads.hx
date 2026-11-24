import haxe.io.Bytes;
import hxn.me.Asset;
import hxn.me.Assets;
import hxn.me.Lifecycle;
import hxn.me.ResMut;
import hxn.me.gpu.Cameras;
import hxn.me.gpu.Gpu;
import hxn.me.gpu.RenderTarget;
import hxn.me.render2d.Atlas;
import hxn.me.render2d.Draw;
import hxn.me.render2d.Typesetter;
import hxn.text.Font;

/**
	Loads an atlas and a font through `Assets`, draws two regions of the atlas
	through a screen camera into a render target, and checks their pixels. The
	atlas image is magenta outside its regions, so a region that samples the
	wrong part of the image shows magenta.
**/
class Loads {
	static final target = new RenderTarget(64, 64);
	static var atlas:Null<Asset<Atlas>>;
	static var font:Null<Asset<Font>>;
	static var shown = -1;
	static var reading = false;

	@:system(Start)
	static function setup(cameras:ResMut<Cameras>, assets:ResMut<Assets>) {
		var main = cameras.main;
		main.projection = Screen;
		main.target = target;
		main.clear = {r: 0, g: 0, b: 0, a: 1};
		var store:Assets = assets;
		store.load(Art.Sheet).then(a -> atlas = a, fail);
		store.load(Art.UiFont).then(f -> font = f, fail);
	}

	// Draws the red region at its own size, and the panel as a nine-slice twice its border.
	@:system(Update)
	static function draw(draw:ResMut<Draw>, gpu:ResMut<Gpu>, typesetter:ResMut<Typesetter>, lifecycle:ResMut<Lifecycle>) {
		if (gpu.failure != null) {
			Sys.println('no GPU: ${gpu.failure}');
			Sys.exit(1);
		}
		if (atlas == null || font == null)
			return;
		var sheet = atlas.value;
		draw.region(sheet.region("red"), 2, 2);
		draw.regionSlice(sheet.region("panel"), 24, 4, 36, 40, 0xFFFFFF, 1, 0, 2);
		if (shown < 0)
			shown = gpu.presented;
		if (gpu.presented < shown + 3 || reading)
			return;
		reading = true;
		var state:Lifecycle = lifecycle;
		var label = (typesetter : Typesetter).text(font.value, "T", {size: 20});
		gpu.device.readTexture(target.texture).then(pixels -> check(pixels, label.width > 0, state), fail);
	}

	static function check(pixels:Bytes, laidOut:Bool, state:Lifecycle) {
		var failed = 0;
		function expect(name:String, x:Int, y:Int, rgb:Array<Int>) {
			var at = (y * 64 + x) * 4;
			var got = [for (c in 0...3) pixels.get(at + c)];
			var ok = [for (c in 0...3) Math.abs(got[c] - rgb[c]) <= 2].indexOf(false) < 0;
			if (!ok)
				failed++;
			Sys.println('$name: ${ok ? "as expected" : 'got ${got.join(", ")}, not ${rgb.join(", ")}'}');
		}
		expect("region", 9, 9, [255, 0, 0]);
		expect("beside the region", 20, 9, [0, 0, 0]);
		expect("nine-slice border", 26, 24, [0, 255, 0]);
		expect("nine-slice top border", 42, 6, [0, 255, 0]);
		expect("nine-slice center", 42, 24, [0, 0, 255]);
		expect("nine-slice edge of the center", 31, 24, [0, 0, 255]);
		Sys.println('text in the loaded font: ${laidOut ? "laid out" : "not laid out"}');
		if (!laidOut)
			failed++;
		// Releasing the atlas closes its texture, which the atlas held through its asset context.
		var texture = atlas.value.texture;
		atlas.release();
		font.release();
		var closed = texture.closed;
		Sys.println('atlas texture after release: ${closed ? "closed" : "still open"}');
		if (!closed)
			failed++;
		if (failed > 0) {
			Sys.println('$failed checks failed');
			Sys.exit(1);
		}
		Sys.println("2D asset checks passed");
		state.quit();
	}

	static function fail(e:haxe.Exception) {
		Sys.println('failed: ${e.message}');
		Sys.exit(1);
	}
}
