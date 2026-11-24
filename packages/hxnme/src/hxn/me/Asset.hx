package hxn.me;

/**
	`Asset` is a handle to a loaded asset. `Assets.load` returns one for each
	load, and every handle to one address and type shares one value. Call
	`release` when the handle is no longer needed. After the last handle is
	released, the value closes.
**/
class Asset<T> {
	/** The path of the file that the asset was loaded from. **/
	public final path:String;

	var entry:Null<AssetEntry>;

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

	/** Returns whether the handle was released. **/
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

