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
import hxn.me.render2d.Region;
import hxn.me.render2d.Texture;
import hxn.me.render2d.Typesetter;
import hxn.text.Font;

/**
	`Loads` loads an atlas and a font through `Assets`, draws two regions of
	the atlas through a screen camera into a render target, and checks their
	pixels. The atlas image is magenta outside its regions, so any region that
	samples the wrong part of the image shows magenta. Then it gives the atlas
	another image and other regions, as a reload does, and checks the pixels again.
**/
class Loads {
	static final target = new RenderTarget(64, 96);
	static var atlas:Null<Asset<ArtSheetAtlas>>;
	static var font:Null<Asset<Font>>;
	static var shown = -1;
	// Holds a sprite of the store whose shadow is white and to its right, so the shadow shows on the black target.
	static var kept:Null<hxn.me.render2d.Sprite>;
	static final beside = new hxn.me.render2d.Shadow(12, 0, 0, 0xFFFFFF, 1);
	static var reading = false;
	// Is the number of presented frames when the atlas changed, or -1 before that.
	static var changed = -1;
	static var failed = 0;

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
	static function draw(draw:ResMut<Draw>, gpu:ResMut<Gpu>, typesetter:ResMut<Typesetter>, lifecycle:ResMut<Lifecycle>,
			sprites:ResMut<hxn.me.render2d.Sprites>) {
		if (gpu.failure != null) {
			Sys.println('no GPU: ${gpu.failure}');
			Sys.exit(1);
		}
		if (atlas == null || font == null)
			return;
		// The atlas has a property for each region, from its file at compile time.
		var sheet = atlas.value;
		// Each region is placed by its pivot, which is the center unless the atlas gives another.
		draw.region(sheet.red, 10, 10);
		draw.region(sheet.feet, 10, 90);
		draw.regionSlice(sheet.panel, 24, 4, 36, 40, 0xFFFFFF, 1, 0, 2);
		// Draws white silhouettes of the red region, sharp and blurred, so they show on the black target.
		draw.shadowOf(sheet.red, 10, 54, 0, 0, 0, 0xFFFFFF, 1);
		draw.shadowOf(sheet.red, 52, 54, 0, 0, 4, 0xFFFFFF, 1);
		var store:hxn.me.render2d.Sprites = sprites;
		if (shown < 0) {
			shown = gpu.presented;
			kept = store.addRegion(sheet.red, 34, 66, beside);
		} else if (gpu.presented == shown + 1)
			// The shadow moves with the sprite.
			store.move(kept, 34, 80);
		if (gpu.presented < (changed < 0 ? shown : changed) + 3 || reading)
			return;
		reading = true;
		var state:Lifecycle = lifecycle;
		if (changed >= 0) {
			gpu.device.readTexture(target.texture).then(pixels -> checkChanged(pixels, state), fail);
			return;
		}
		var label = (typesetter : Typesetter).text(font.value, "T", {size: 20});
		gpu.device.readTexture(target.texture).then(pixels -> {
			check(pixels, label.width > 0);
			change();
			changed = gpu.presented;
			reading = false;
		}, fail);
	}

	static function expectIn(pixels:Bytes, name:String, x:Int, y:Int, rgb:Array<Int>) {
		var at = (y * 64 + x) * 4;
		var got = [for (c in 0...3) pixels.get(at + c)];
		var ok = [for (c in 0...3) Math.abs(got[c] - rgb[c]) <= 2].indexOf(false) < 0;
		if (!ok)
			failed++;
		Sys.println('$name: ${ok ? "as expected" : 'got ${got.join(", ")}, not ${rgb.join(", ")}'}');
	}

	static function check(pixels:Bytes, laidOut:Bool) {
		var expect = expectIn.bind(pixels);
		expect("region", 9, 9, [255, 0, 0]);
		expect("beside the region", 20, 9, [0, 0, 0]);
		expect("nine-slice border", 26, 24, [0, 255, 0]);
		expect("nine-slice top border", 42, 6, [0, 255, 0]);
		expect("nine-slice center", 42, 24, [0, 0, 255]);
		expect("nine-slice edge of the center", 31, 24, [0, 0, 255]);
		expect("region with its pivot at its feet", 9, 82, [255, 0, 0]);
		expect("above the feet region", 9, 70, [0, 0, 0]);
		expect("below the feet region", 9, 93, [0, 0, 0]);
		expect("sprite of the store over its shadow", 40, 80, [255, 0, 0]);
		expect("shadow of the sprite beside it", 50, 80, [255, 255, 255]);
		expect("where the shadow was before the sprite moved", 50, 66, [0, 0, 0]);
		expect("sharp shadow of the region", 9, 54, [255, 255, 255]);
		expect("beside the sharp shadow", 20, 54, [0, 0, 0]);
		expect("middle of the blurred shadow", 52, 54, [255, 255, 255]);
		var edge = pixels.get((54 * 64 + 44) * 4);
		var blurred = edge > 60 && edge < 200;
		if (!blurred)
			failed++;
		Sys.println('edge of the blurred shadow: ${blurred ? "part covered" : 'got $edge'}');
		Sys.println('text in the loaded font: ${laidOut ? "laid out" : "not laid out"}');
		if (!laidOut)
			failed++;
	}

	// Gives the atlas a green image of another size, and other rectangles and pivots.
	static function change() {
		var sheet:Atlas = atlas.value;
		var red = sheet.region("red");
		var pixels = Bytes.alloc(80 * 40 * 4);
		for (i in 0...80 * 40)
			pixels.setInt32(i * 4, 0xFF00FF00);
		@:privateAccess sheet.texture.adopt(new Texture(80, 40, pixels));
		var next = new Atlas(sheet.texture);
		next.add(new Region("feet", sheet.texture, 4, 4, 16, 16));
		next.add(new Region("panel", sheet.texture, 40, 4, 30, 30, 3, 3, 3, 3));
		next.add(new Region("red", sheet.texture, 20, 4, 16, 16, 0, 0, 0, 0, 0, 0.5));
		var taken = @:privateAccess sheet.adopt(next) && sheet.region("red") == red && red.x == 20 && sheet.texture.width == 80;
		Sys.println('the atlas takes another image and other regions: ${taken ? "yes" : "no"}');
		if (!taken)
			failed++;
	}

	static function checkChanged(pixels:Bytes, state:Lifecycle) {
		var expect = expectIn.bind(pixels);
		expect("region of the new image", 14, 10, [0, 255, 0]);
		expect("left of its new pivot", 7, 10, [0, 0, 0]);
		expect("sprite of the store in the new image", 40, 80, [0, 255, 0]);
		expect("left of its new pivot", 30, 80, [0, 0, 0]);
		expect("shadow of that sprite", 56, 80, [255, 255, 255]);
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
