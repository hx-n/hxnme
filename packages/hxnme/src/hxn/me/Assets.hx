package hxn.me;

#if !macro
import haxe.ds.StringMap;
import haxe.io.Bytes;
import hxn.Future;
import hxn.assets.AssetCatalog;
import hxn.assets.AssetLoader;
import hxn.assets.FileSource;
import hxn.file.Storage;
#end

/**
	`Assets` is the kernel resource that loads the app's assets with
	hxn-assets. The app declares its assets as fields of type `AssetRef<T>` on
	a class built with `@:build(hxn.me.Assets.build())`:

	```haxe
	@:build(hxn.me.Assets.build())
	class GameAssets {
		@:asset("ui/sheet.json") public static var Sheet:AssetRef<Atlas>;
		@:asset("levels/start.json") public static var Start:LevelData;
	}
	```

	`load(GameAssets.Sheet)` returns a handle when the asset is ready. Loads
	of one asset share one value. When the last handle to it is released, the
	value closes and its bytes are unloaded. Fields of other types are
	hxn-assets fields, such as data that is decoded at compile time.
**/
class Assets {
	/** The build macro for a class of asset declarations. It runs hxn-assets' macro on the class too. **/
	public static macro function build():Array<haxe.macro.Expr.Field>
		return hxn.me.macro.AssetFields.build();

	#if !macro
	final entries = new StringMap<AssetEntry>();
	final loaders = new StringMap<AssetLoader>();
	var storage:Null<Storage>;
	var source:Null<FileSource>;

	public function new() {}

	/**
		Loads the asset that `ref` declares. The future gives a handle to its
		value, or fails if the asset cannot be read or decoded.
	**/
	public function load<T>(ref:AssetRef<T>):Future<Asset<T>> {
		var loader = loaders.get(ref.source());
		if (loader == null) {
			loader = new AssetLoader(files(), ref.list());
			loaders.set(ref.source(), loader);
		}
		var from = loader;
		return open(ref.source() + "\n" + ref.address, ref.path, ref.decoder(), () -> from.load(ref.address), () -> from.unload(ref.address));
	}

	/**
		Loads the bundled file at `path` and decodes it as `type`. Decoders use
		it, through `AssetContext`, for files that an asset lists, such as the
		image of an atlas. If the app declares assets, the file must be one of
		them, because only declared files are bundled.
	**/
	public function loadFile<T>(path:String, type:AssetType<T>):Future<Asset<T>>
		return open("\n" + path, path, type, () -> files().read(path), () -> {});

	/** Returns the number of assets that are loaded or loading. **/
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
			l.close();
		loaders.clear();
		if (storage != null)
			storage.close();
		storage = null;
		source = null;
	}

	function open<T>(where:String, path:String, type:AssetType<T>, read:() -> Future<Bytes>, unload:() -> Void):Future<Asset<T>> {
		var key = type.name + "\n" + where;
		var entry = entries.get(key);
		if (entry == null) {
			var made = new AssetEntry(this, key, path, cast type, unload);
			entries.set(key, made);
			var context = new AssetContext(this, made);
			made.ready = read().flatMap(bytes -> (cast type : AssetType<Dynamic>).decode(bytes, context)).map(value -> {
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

	// Counts down the handles of `entry`, and closes its value after the last one.
	@:allow(hxn.me) function drop(entry:AssetEntry):Void {
		entry.count--;
		if (entry.count > 0)
			return;
		forget(entry);
		if (entry.value != null)
			entry.type.close(entry.value);
		entry.unload();
	}

	// Removes `entry` and releases the assets that its value holds.
	function forget(entry:AssetEntry):Void {
		if (entries.get(entry.key) == entry)
			entries.remove(entry.key);
		for (held in entry.held)
			held.release();
		entry.held.resize(0);
	}

	function files():FileSource {
		if (source == null) {
			storage = new Storage(Project.text("app.id", "hxnme"));
			source = new FileSource(storage);
		}
		return source;
	}
	#end
}
