import hxn.me.AssetRef;
import hxn.me.render2d.Atlas;
import hxn.me.render2d.Texture;
import hxn.text.Font;

/** `Art` declares the assets of the check. It declares the atlas image too, so that the image is bundled. **/
@:build(hxn.me.Assets.build())
class Art {
	@:asset("sheet.png")
	public static var SheetImage:AssetRef<Texture>;

	@:asset("sheet.json")
	public static var Sheet:AssetRef<Atlas>;

	@:asset("font.ttf")
	public static var UiFont:AssetRef<Font>;
}
