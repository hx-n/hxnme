package hxn.me;

import hxn.assets.AssetCatalog;

/**
	`AssetRef` refers to an asset that a class built with
	`@:build(hxn.me.Assets.build())` declares, and how it decodes.
	`Assets.load` takes it. The macro makes one for each field of type
	`AssetRef<T>`.
**/
class AssetRef<T> {
	/** The asset's address in its class's catalog. **/
	public final address:String;

	/** The path of the asset's file in the bundled assets. **/
	public final path:String;

	final type:AssetType<T>;
	final owner:String;
	final catalog:() -> AssetCatalog;

	@:noCompletion public function new(address:String, path:String, type:AssetType<T>, owner:String, catalog:() -> AssetCatalog) {
		this.address = address;
		this.path = path;
		this.type = type;
		this.owner = owner;
		this.catalog = catalog;
	}

	@:allow(hxn.me) function decoder():AssetType<T>
		return type;

	@:allow(hxn.me) function source():String
		return owner;

	@:allow(hxn.me) function list():AssetCatalog
		return catalog();
}
