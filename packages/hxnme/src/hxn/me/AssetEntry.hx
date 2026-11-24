package hxn.me;

/** Each entry holds one loaded value, the number of handles to it, and the assets that it holds. **/
@:allow(hxn.me)
@:noCompletion
class AssetEntry {
	final assets:Assets;
	final key:String;
	final address:String;
	final type:AssetType<Dynamic>;
	var value:Dynamic;
	var ready:Null<hxn.Future<Dynamic>>;
	var count = 0;
	final held:Array<Asset<Dynamic>> = [];

	function new(assets:Assets, key:String, address:String, type:AssetType<Dynamic>) {
		this.assets = assets;
		this.key = key;
		this.address = address;
		this.type = type;
	}
}
