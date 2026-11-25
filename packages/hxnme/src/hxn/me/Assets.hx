package hxn.me;

#if !macro
import haxe.ds.StringMap;
import haxe.io.Bytes;
import hxn.Future;
import hxn.assets.AssetCatalog;
import hxn.assets.AssetLoader;
import hxn.assets.AssetSource;
import hxn.assets.FileSource;
import hxn.file.Storage;
#end

/**
	`Assets` loads the app's assets with hxn-assets. It is a kernel resource.
	The app declares its assets as fields of type `AssetRef<T>` on a class
	built with `@:build(hxn.me.Assets.build())`:

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
	hxn-assets fields, such as data that hxn-assets decodes at compile time.
**/
class Assets {
	/** Builds a class of asset declarations. It also runs hxn-assets' macro on the class. **/
	public static macro function build():Array<haxe.macro.Expr.Field>
		return hxn.me.macro.AssetFields.build();

	#if !macro
	final entries = new StringMap<AssetEntry>();
	final loaders = new StringMap<AssetLoader>();
	var storage:Null<Storage>;
	var source:Null<AssetSource>;

	#if hxnme_dev
	/** The assets of the app, for `hxn.me.dev.Session`. **/
	@:allow(hxn.me) static var current:Null<Assets> = null;

	// Holds the files that changed while the app runs, by path.
	final changed = new Map<String, Bytes>();
	#end

	public function new() {
		#if hxnme_dev
		current = this;
		#end
	}

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
		them, because hxn-assets bundles only declared files.
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
			var context = new AssetContext(this, path, made.held);
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

	function files():AssetSource {
		if (source == null) {
			storage = new Storage(Project.text("app.id", "hxnme"));
			source = new FileSource(storage);
			#if hxnme_dev
			source = new hxn.me.dev.ChangedSource(source, changed);
			#end
		}
		return source;
	}

	#if hxnme_dev
	/**
		Loads the assets that `files` changes again, and those that hold them. Their
		handles then give the new values. The future resolves after all of them are
		ready.
	**/
	@:allow(hxn.me) function update(files:Map<String, Bytes>):Future<Bool> {
		var stale:Array<AssetEntry> = [];
		for (path => bytes in files) {
			changed.set(path, bytes);
			var loaded = [for (entry in entries) if (entry.path == path) entry];
			if (loaded.length == 0 && (AssetRef.declared == null || !AssetRef.declared.contains(path)))
				hxn.me.dev.Session.restart('$path changed');
			stale = stale.concat(loaded);
		}
		// The loaders keep the bytes of files that did change, and the catalogs the digests.
		loaders.clear();
		return reloadAll(stale);
	}

	// Loads each entry again before the entries that hold it.
	function reloadAll(stale:Array<AssetEntry>):Future<Bool> {
		if (stale.length == 0)
			return Future.resolved(true);
		var next = stale[0];
		for (entry in stale)
			if (!Lambda.exists(entry.held, asset -> stale.contains(asset.entry))) {
				next = entry;
				break;
			}
		stale.remove(next);
		return reload(next).flatMap(replaced -> {
			if (replaced)
				for (entry in entries)
					if (!stale.contains(entry) && Lambda.exists(entry.held, asset -> asset.entry == next))
						stale.push(entry);
			return reloadAll(stale);
		});
	}

	// Decodes the file of `entry` again. Returns whether the entry has the new value.
	function reload(entry:AssetEntry):Future<Bool> {
		var held:Array<Asset<Dynamic>> = [];
		function drop(assets:Array<Asset<Dynamic>>)
			for (asset in assets)
				asset.release();
		return entry.ready.flatMap(_ -> files().read(entry.path))
			.flatMap(bytes -> entry.type.decode(bytes, new AssetContext(this, entry.path, held)))
			.map(value -> {
				var kept = entries.get(entry.key) == entry ? entry.type.replace(entry.value, value) : null;
				if (kept == null) {
					if (entries.get(entry.key) == entry)
						hxn.me.dev.Session.restart('${entry.path} changed');
					entry.type.close(value);
					drop(held);
					return false;
				}
				var before = entry.held;
				entry.value = kept;
				entry.held = held;
				entry.revision++;
				drop(before);
				return true;
			})
			.recover(error -> {
				drop(held);
				hxn.me.dev.Session.say('${entry.path} does not load, and the app keeps the value from before: ${error.message}');
				return Future.resolved(false);
			});
	}
	#end
	#end
}
