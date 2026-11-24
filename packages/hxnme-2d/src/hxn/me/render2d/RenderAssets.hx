package hxn.me.render2d;

import haxe.io.Bytes;
import hxn.Future;
import hxn.me.AssetContext;
import hxn.me.AssetType;
import hxn.text.Font;

/**
	The asset types of the 2D renderer. `Texture`, `Atlas` and
	`hxn.text.Font` name them with `@:assetType`, so `AssetRef<Texture>`,
	`AssetRef<Atlas>` and `AssetRef<Font>` fields use them.
**/
class RenderAssets {
	/** A PNG image as a `Texture`. The texture closes with the asset. **/
	public static final texture = new AssetType<Texture>("hxnme-2d texture", (bytes, _) -> try {
		var image = hxn.assets.AssetDecode.png(bytes);
		Future.resolved(new Texture(image.width, image.height, image.pixels));
	} catch (e:haxe.Exception) Future.rejected(e), t -> t.close());

	/** A TTF, OpenType or WOFF2 file as an `hxn.text.Font`, for `Typesetter.text`. **/
	public static final font = new AssetType<Font>("hxnme-2d font", (bytes, _) -> try Future.resolved(new Font(bytes, {})) catch (e:haxe.Exception)
		Future.rejected(e), f -> f.close());

	/** A JSON file of regions, and the image it lists, as an `Atlas`. The image must be declared too, so that it is bundled. **/
	public static final atlas = new AssetType<Atlas>("hxnme-2d atlas", decodeAtlas);

	static function decodeAtlas(bytes:Bytes, context:AssetContext):Future<Atlas> {
		var data:Dynamic = try haxe.Json.parse(bytes.toString()) catch (e:haxe.Exception) return Future.rejected(e);
		if (!Std.isOfType(data.image, String))
			return Future.rejected(new haxe.Exception('the atlas ${context.path} has no image'));
		return context.load(context.resolve(data.image), texture).map(image -> {
			var made = new Atlas(image);
			var regions:Dynamic = data.regions;
			if (regions != null)
				for (name in Reflect.fields(regions)) {
					var r:Dynamic = Reflect.field(regions, name);
					var slice:Array<Int> = r.slice != null ? r.slice : [0, 0, 0, 0];
					made.add(new Region(name, image, r.x, r.y, r.width, r.height, slice[0], slice[1], slice[2], slice[3]));
				}
			made;
		});
	}
}
