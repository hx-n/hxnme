/** The check's hxn-assets catalog. With a catalog, only the files it lists are bundled. **/
@:build(hxn.assets.Assets.build())
class Catalog {
	@:asset("notes/greeting.txt")
	@:dynamicAsset
	public static var Greeting:String;

	@:asset("notes/other.txt")
	@:dynamicAsset
	public static var Other:String;

	@:asset("level.json")
	@:dynamicAsset
	public static var Level:Dynamic;
}
