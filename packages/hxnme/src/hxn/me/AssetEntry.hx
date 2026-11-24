package hxn.me;

/** Each entry holds one loaded value, the number of handles to it, and the assets that it holds. **/
@:allow(hxn.me)
@:noCompletion
class AssetEntry {
	final assets:Assets;
	final key:String;
	// The path of the asset's file, which `AssetContext.resolve` resolves against.
	final path:String;
	final type:AssetType<Dynamic>;
	var value:Dynamic;
	var ready:Null<hxn.Future<Dynamic>>;
	var count = 0;
	final held:Array<Asset<Dynamic>> = [];
	final unload:() -> Void;

	function new(assets:Assets, key:String, path:String, type:AssetType<Dynamic>, unload:() -> Void) {
		this.assets = assets;
		this.key = key;
		this.path = path;
		this.type = type;
		this.unload = unload;
	}
}
