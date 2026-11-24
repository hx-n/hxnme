import hxn.me.AssetRef;
import hxn.me.render2d.Atlas;
import hxn.me.render2d.Texture;
import hxn.text.Font;

/** `GameAssets` declares the game's assets, which are in the `assets` directory. hxn-assets bundles only declared files, so the class declares the atlas image too. **/
@:build(hxn.me.Assets.build())
class GameAssets {
	@:asset("sheet.png")
	public static var SheetImage:AssetRef<Texture>;

	@:asset("sheet.json")
	public static var Sheet:AssetRef<Atlas>;

	@:asset("font.ttf")
	public static var Ui:AssetRef<Font>;
}
