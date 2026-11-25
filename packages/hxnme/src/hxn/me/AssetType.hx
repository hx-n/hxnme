package hxn.me;

import haxe.io.Bytes;
import hxn.Future;

/**
	`AssetType` turns an asset's bytes into a value of type `T` for
	`Assets.load`, and closes the value after the last handle to it is
	released. Plugins provide types for their objects, such as the textures
	of hxnme-2d, and put `@:assetType(expr)` on the class so that
	`AssetRef<Class>` fields find the type. hxn-assets decodes data types
	itself.
**/
class AssetType<T> {
	/** The name that keeps loads of one address with different types apart. **/
	public final name:String;

	final decoder:(Bytes, AssetContext) -> Future<T>;
	final closer:Null<T->Void>;
	final replacer:Null<(T, T) -> Bool>;

	/**
		Makes a type called `name`. `decode` turns the bytes into a value, and
		loads through its `AssetContext` the other assets that the value holds.
		`close` releases what the value holds outside the heap, such as a GPU
		texture. After the file changes under `hxn me dev`, `replace` gives
		the first value the contents of the second, so that everything which
		holds the first one shows the change. It returns false if it cannot.
		Without `replace`, the new value takes the place of the old one in the
		handles, and the app restarts instead if the type has `close`.
	**/
	public function new(name:String, decode:(Bytes, AssetContext) -> Future<T>, ?close:T->Void, ?replace:(T, T) -> Bool) {
		this.name = name;
		decoder = decode;
		closer = close;
		replacer = replace;
	}

	@:allow(hxn.me) function decode(bytes:Bytes, context:AssetContext):Future<T>
		return decoder(bytes, context);

	// Returns the value to keep after the file of `value` changed and decodes to `by`, or null if neither can stay.
	@:allow(hxn.me) function replace(value:T, by:T):Null<T> {
		if (replacer != null)
			return replacer(value, by) ? value : null;
		return closer == null ? by : null;
	}

	@:allow(hxn.me) function close(value:T):Void
		if (closer != null)
			closer(value);
}
