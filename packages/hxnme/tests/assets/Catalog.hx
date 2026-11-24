import hxn.me.AssetRef;

typedef LevelData = {name:String, lives:Int};

/** The check's asset declarations. With a declaration class, only the files it lists are bundled. **/
@:build(hxn.me.Assets.build())
class Catalog {
	// Types.counted counts how often it decodes and closes its value, so the check can test sharing and release.
	@:asset("notes/greeting.txt") @:assetType(Types.counted)
	public static var Greeting:AssetRef<String>;

	// Types.pair reads greeting.txt and also loads other.txt from the same directory, as an atlas loads its image.
	// The value is both texts. Releasing Pair also releases other.txt.
	@:asset("Pair", "notes/greeting.txt") @:assetType(Types.pair)
	public static var Pair:AssetRef<String>;

	// hxn-assets decodes these by their declared types: text, and JSON checked against LevelData.
	@:asset("notes/other.txt")
	public static var Other:AssetRef<String>;

	@:asset("level.json")
	public static var Level:AssetRef<LevelData>;

	// hxn-assets decodes this at compile time and embeds the value, so it needs no load.
	@:asset("Embedded", "level.json")
	public static var Embedded:LevelData;

	// This file is declared but missing, so its load fails.
	@:asset("notes/none.txt")
	public static var None:AssetRef<String>;
}
