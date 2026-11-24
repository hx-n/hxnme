import hxn.me.AssetRef;
import hxn.me.render2d.Atlas;
import hxn.me.render2d.Texture;
import hxn.text.Font;

/** The game's assets, in the `assets` directory. Only declared files are bundled, so the atlas image is declared too. **/
@:build(hxn.me.Assets.build())
class GameAssets {
	@:asset("sheet.png")
	public static var SheetImage:AssetRef<Texture>;

	@:asset("sheet.json")
	public static var Sheet:AssetRef<Atlas>;

	@:asset("font.ttf")
	public static var Ui:AssetRef<Font>;
}
