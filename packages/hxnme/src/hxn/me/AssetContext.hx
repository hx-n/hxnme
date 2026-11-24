package hxn.me;

import hxn.Future;

/**
	`AssetContext` is what a decoder of an `AssetType` gets besides the bytes:
	the asset's address, and loads of the other assets that its value holds.
	The context keeps a handle to each of those, and releases them after the
	value closes.
**/
class AssetContext {
	/** The path of the file of the asset that is being decoded. **/
	public final path:String;

	final assets:Assets;
	final entry:AssetEntry;

	@:allow(hxn.me) function new(assets:Assets, entry:AssetEntry) {
		this.assets = assets;
		this.entry = entry;
		path = entry.path;
	}

	/** Loads the bundled file at `path` as `type`, held until the value of this asset closes. **/
	public function load<T>(path:String, type:AssetType<T>):Future<T>
		return assets.loadFile(path, type).map(asset -> {
			entry.held.push(cast asset);
			asset.value;
		});

	/** Returns `relative`, a path relative to the directory of this asset's file, as a path in the bundled assets. **/
	public function resolve(relative:String):String {
		var slash = path.lastIndexOf("/");
		return slash < 0 ? relative : path.substr(0, slash + 1) + relative;
	}
}
