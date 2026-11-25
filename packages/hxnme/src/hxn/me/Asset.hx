package hxn.me;

/**
	`Asset` gives access to the value of a loaded asset. `Assets.load` returns
	one handle for each load, and every handle to one address and type shares
	one value. When the app no longer needs the handle, call `release`. After
	the app releases the last handle, the value closes.
**/
class Asset<T> {
	/** The path of the file that `Assets` loaded the asset from. **/
	public final path:String;

	@:allow(hxn.me) var entry:Null<AssetEntry>;

	@:allow(hxn.me) function new(entry:AssetEntry) {
		this.entry = entry;
		path = entry.path;
	}

	/** The loaded value. Reading it after `release` throws. **/
	public var value(get, never):T;

	function get_value():T {
		if (entry == null)
			throw 'the asset $path was released';
		return entry.value;
	}

	/**
		The number of times that `hxn me dev` replaced the value after its file
		changed. Systems that build something from the value can compare it to
		build that again.
	**/
	public var revision(get, never):Int;

	function get_revision():Int
		return entry == null ? 0 : entry.revision;

	/** Returns whether the app released the handle. **/
	public var released(get, never):Bool;

	function get_released():Bool
		return entry == null;

	/** Releases the handle. Releasing it again does nothing. **/
	public function release():Void {
		var held = entry;
		if (held == null)
			return;
		entry = null;
		held.assets.drop(held);
	}
}

