import hxn.me.AssetRef;
import hxn.me.render2d.Atlas;
import hxn.me.render2d.Texture;
import hxn.text.Font;

/** The check's asset declarations. The atlas image is declared too, so that it is bundled. **/
@:build(hxn.me.Assets.build())
class Art {
	@:asset("sheet.png")
	public static var SheetImage:AssetRef<Texture>;

	@:asset("sheet.json")
	public static var Sheet:AssetRef<Atlas>;

	@:asset("font.ttf")
	public static var UiFont:AssetRef<Font>;
}
