package hxn.me.dev;

#if hxnme_dev
import haxe.io.Bytes;
import hxn.Future;
import hxn.assets.AssetSource;

/** `ChangedSource` reads the files that changed while the app runs from memory, and every other file from `source`. **/
@:noCompletion
class ChangedSource implements AssetSource {
	final source:AssetSource;
	final changed:Map<String, Bytes>;

	public function new(source:AssetSource, changed:Map<String, Bytes>) {
		this.source = source;
		this.changed = changed;
	}

	public function read(path:String):Future<Bytes>
		return changed.exists(path) ? Future.resolved(changed.get(path)) : source.read(path);
}
#end
