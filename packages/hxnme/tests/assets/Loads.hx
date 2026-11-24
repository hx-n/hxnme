import hxn.me.Asset;
import hxn.me.Assets;
import hxn.me.Lifecycle;
import hxn.me.ResMut;

/**
	Loads the assets that `Catalog` declares in the first frame, and tests
	what the handles share, close and release in the frames after.
**/
class Loads {
	static var first:Null<Asset<String>>;
	static var second:Null<Asset<String>>;
	static var pair:Null<Asset<String>>;
	static var level:Null<Asset<Catalog.LevelData>>;
	static var other:Null<Asset<String>>;
	static var missing = "";
	static var frames = 0;
	static var failed = 0;

	@:system(Start)
	static function start(assets:ResMut<Assets>) {
		var store:Assets = assets;
		store.load(Catalog.Greeting).then(a -> first = a, fail);
		store.load(Catalog.Greeting).then(a -> second = a, fail);
		store.load(Catalog.Pair).then(a -> pair = a, fail);
		store.load(Catalog.Level).then(a -> level = a, fail);
		store.load(Catalog.Other).then(a -> other = a, fail);
		store.load(Catalog.None).then(_ -> missing = "loaded", e -> missing = "failed");
	}

	@:system(Update)
	static function check(assets:ResMut<Assets>, lifecycle:ResMut<Lifecycle>) {
		var store:Assets = assets;
		frames++;
		if (first == null || second == null || pair == null || level == null || other == null || missing == "") {
			if (frames > 600)
				finish(lifecycle, "the loads did not finish");
			return;
		}
		expect("two loads of one asset share one decode", Types.decodes == 1 && first.value == "hello" && second.value == "hello");
		expect("JSON decodes to its declared type", level.value.name == "start" && level.value.lives == 3);
		expect("text decodes", other.value == "world");
		expect("an embedded field holds its value", Catalog.Embedded.name == "start");
		expect("a missing file fails", missing == "failed");
		expect("a value holds what it depends on", pair.value == "hello world");
		var before = store.loaded;
		first.release();
		expect("the value stays while a handle holds it", Types.closes == 0 && second.value == "hello");
		second.release();
		expect("the last release closes the value", Types.closes == 1 && second.released && store.loaded == before - 1);
		second.release();
		expect("a second release does nothing", Types.closes == 1);
		pair.release();
		expect("a value releases what it depends on", Types.closedNotes == 1);
		level.release();
		other.release();
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
