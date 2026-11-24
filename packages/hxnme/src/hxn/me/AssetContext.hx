package hxn.me;

import hxn.Future;

/**
	`AssetContext` is what a decoder of an `AssetType` gets besides the bytes:
	the asset's address, and loads of the other assets that its value holds.
	The context keeps a handle to each of those, and releases them after the
	value closes.
**/
class AssetContext {
	/** The address of the asset that is being decoded. **/
	public final address:String;

	final assets:Assets;
	final entry:AssetEntry;

	@:allow(hxn.me) function new(assets:Assets, entry:AssetEntry) {
		this.assets = assets;
		this.entry = entry;
		address = entry.address;
	}

	/** Loads `address` as `type`, held until the value of this asset closes. **/
	public function load<T>(address:String, type:AssetType<T>):Future<T>
		return assets.load(address, type).map(asset -> {
			entry.held.push(cast asset);
			asset.value;
		});

	/** Returns `path`, which is relative to the directory of this asset, as an address. **/
	public function resolve(path:String):String {
		var slash = address.lastIndexOf("/");
		return slash < 0 ? path : address.substr(0, slash + 1) + path;
	}
}
