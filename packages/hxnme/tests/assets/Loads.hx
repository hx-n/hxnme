import haxe.io.Bytes;
import hxn.Future;
import hxn.me.Asset;
import hxn.me.AssetType;
import hxn.me.AssetTypes;
import hxn.me.Assets;
import hxn.me.Lifecycle;
import hxn.me.ResMut;

/**
	Loads files of the check's `assets` directory in the first frame, and
	tests what the handles share, close and release in the frames after.
**/
class Loads {
	static var decodes = 0;
	static var closes = 0;
	static var closedNotes = 0;

	// Text that counts its decodes and closes.
	static final counted = new AssetType<String>("counted", (bytes, _) -> {
		decodes++;
		Future.resolved(bytes.toString());
	}, _ -> closes++);

	static final note = new AssetType<String>("note", (bytes, _) -> Future.resolved(bytes.toString()), _ -> closedNotes++);

	// Text that holds another note, the file named in it, as a value it depends on.
	static final pair = new AssetType<String>("pair", (bytes, context) -> context.load(context.resolve("other.txt"), note)
		.map(other -> bytes.toString() + " " + other));

	static var first:Null<Asset<String>>;
	static var second:Null<Asset<String>>;
	static var both:Null<Asset<String>>;
	static var level:Null<Asset<Dynamic>>;
	static var listed:Null<Asset<String>>;
	static var missing = "";
	static var frames = 0;
	static var failed = 0;

	@:system(Start)
	static function start(assets:ResMut<Assets>) {
		var store:Assets = assets;
		store.add(Catalog.catalog());
		store.load("notes/greeting.txt", counted).then(a -> first = a, fail);
		store.load("notes/greeting.txt", counted).then(a -> second = a, fail);
		store.load("notes/greeting.txt", pair).then(a -> both = a, fail);
		store.load("level.json", AssetTypes.json).then(a -> level = a, fail);
		store.load(Catalog.addresses.Other, AssetTypes.text).then(a -> listed = a, fail);
		store.load("notes/none.txt", AssetTypes.bytes).then(_ -> missing = "loaded", e -> missing = "failed");
	}

	@:system(Update)
	static function check(assets:ResMut<Assets>, lifecycle:ResMut<Lifecycle>) {
		var store:Assets = assets;
		frames++;
		if (first == null || second == null || both == null || level == null || listed == null || missing == "") {
			if (frames > 600)
				finish(lifecycle, "the loads did not finish");
			return;
		}
		expect("two loads of one address share one decode", decodes == 1 && first.value == "hello" && second.value == "hello");
		expect("JSON decodes", level.value.name == "start" && level.value.lives == 3);
		expect("a catalog address loads", listed.value == "world");
		expect("a missing file fails", missing == "failed");
		expect("a value holds what it depends on", both.value == "hello world");
		var before = store.loaded;
		first.release();
		expect("the value stays while a handle holds it", closes == 0 && second.value == "hello");
		second.release();
		expect("the last release closes the value", closes == 1 && second.released && store.loaded == before - 1);
		second.release();
		expect("a second release does nothing", closes == 1);
		both.release();
		expect("a value releases what it depends on", closedNotes == 1);
		level.release();
		listed.release();
		expect("nothing is loaded after every release", store.loaded == 0);
		finish(lifecycle, failed == 0 ? null : '$failed checks failed');
	}

	static function expect(name:String, ok:Bool) {
		if (!ok)
			failed++;
		Sys.println('$name: ${ok ? "yes" : "no"}');
	}

	static function fail(e:haxe.Exception) {
		Sys.println('a load failed: ${e.message}');
		Sys.exit(1);
	}

	static function finish(lifecycle:ResMut<Lifecycle>, failure:Null<String>) {
		if (failure != null) {
			Sys.println(failure);
			Sys.exit(1);
		}
		Sys.println("Asset checks passed");
		(lifecycle : Lifecycle).quit();
	}
}
