package hxn.me;

import hxn.Future;

/**
	`AssetContext` gives the decoder of an `AssetType` the address of the
	asset, and loads the other assets that the value of the asset holds. The
	decoder gets the context together with the bytes. The context keeps a
	handle to each of those assets, and releases them after the value closes.
**/
class AssetContext {
	/** The path of the file of the asset that the decoder decodes. **/
	public final path:String;

	final assets:Assets;
	final held:Array<Asset<Dynamic>>;

	@:allow(hxn.me) function new(assets:Assets, path:String, held:Array<Asset<Dynamic>>) {
		this.assets = assets;
		this.path = path;
		this.held = held;
	}

	/** Loads the bundled file at `path` as `type`, and holds it until the value of this asset closes. **/
	public function load<T>(path:String, type:AssetType<T>):Future<T>
		return assets.loadFile(path, type).map(asset -> {
			held.push(cast asset);
			asset.value;
		});

	/** Resolves `relative`, a path relative to the directory of this asset's file, to a path in the bundled assets. **/
	public function resolve(relative:String):String {
		var slash = path.lastIndexOf("/");
		return slash < 0 ? relative : path.substr(0, slash + 1) + relative;
	}
}
