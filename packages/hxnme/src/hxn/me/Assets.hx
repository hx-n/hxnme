package hxn.me;

import haxe.ds.StringMap;
import haxe.io.Bytes;
import hxn.Future;
import hxn.assets.AssetCatalog;
import hxn.assets.AssetLoader;
import hxn.assets.FileSource;
import hxn.file.Storage;

/**
	`Assets` is the kernel resource that loads the app's assets with
	hxn-assets. `load` reads an address and decodes it with an `AssetType`,
	and returns a handle when it is ready. Loads of one address and type share
	one value. When the last handle to it is released, the value closes and
	its bytes are unloaded.

	Bundled files come from the `assets` directory, which hxn-assets copies
	beside the program at compile time. If the app declares no hxn-assets
	catalog class, every file is bundled. If it declares one, only the files
	that its catalogs list are bundled. An address that a catalog added with
	`add` lists, such as `GameAssets.addresses.Hero`, loads with that
	catalog's dependencies and content checks. Any other address is a path in
	`assets`. `app.id` in `hxnme.toml` names the app's storage.
**/
class Assets {
	final entries = new StringMap<AssetEntry>();
	final loaders:Array<{catalog:AssetCatalog, loader:AssetLoader}> = [];
	var storage:Null<Storage>;
	var source:Null<FileSource>;

	public function new() {}

	/** Adds the addresses of `catalog`, such as `GameAssets.catalog()` of an hxn-assets class. **/
	public function add(catalog:AssetCatalog):Void
		loaders.push({catalog: catalog, loader: new AssetLoader(files(), catalog)});

	/**
		Loads `address` and decodes it as `type`, such as `AssetTypes.json`.
		The future gives a handle to the value, or fails if the asset cannot be
		read or decoded.
	**/
	public function load<T>(address:String, type:AssetType<T>):Future<Asset<T>> {
		var key = type.name + "\n" + address;
		var entry = entries.get(key);
		if (entry == null) {
			var made = new AssetEntry(this, key, address, cast type);
			entries.set(key, made);
			var context = new AssetContext(this, made);
			made.ready = read(address).flatMap(bytes -> (cast type : AssetType<Dynamic>).decode(bytes, context)).map(value -> {
				made.value = value;
				value;
			});
			made.ready.then(_ -> {}, _ -> forget(made));
			entry = made;
		}
		entry.count++;
		var shared = entry;
		return entry.ready.map(_ -> new Asset<T>(shared));
	}

	/** Returns the number of addresses and types that are loaded or loading. **/
	public var loaded(get, never):Int;

	function get_loaded():Int {
		var n = 0;
		for (_ in entries)
			n++;
		return n;
	}

	/** Closes the storage and the loaders. Values that handles still hold stay as they are. **/
	public function close():Void {
		for (l in loaders)
			l.loader.close();
		loaders.resize(0);
		if (storage != null)
			storage.close();
		storage = null;
		source = null;
	}

	// Counts down the handles of `entry`, and closes its value after the last one.
	@:allow(hxn.me) function drop(entry:AssetEntry):Void {
		entry.count--;
		if (entry.count > 0)
			return;
		forget(entry);
		if (entry.value != null)
			entry.type.close(entry.value);
		for (l in loaders)
			if (has(l.catalog, entry.address))
				l.loader.unload(entry.address);
	}

	// Removes `entry` and releases the assets that its value holds.
	function forget(entry:AssetEntry):Void {
		if (entries.get(entry.key) == entry)
			entries.remove(entry.key);
		for (held in entry.held)
			held.release();
		entry.held.resize(0);
	}

	function read(address:String):Future<Bytes> {
		for (l in loaders)
			if (has(l.catalog, address))
				return l.loader.load(address);
		return files().read(address);
	}

	static function has(catalog:AssetCatalog, address:String):Bool
		return try catalog.get(address) != null catch (_:Dynamic) false;

	function files():FileSource {
		if (source == null) {
			storage = new Storage(Project.text("app.id", "hxnme"));
			source = new FileSource(storage);
		}
		return source;
	}
}
