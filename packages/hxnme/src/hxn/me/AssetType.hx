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

	/**
		Makes a type called `name`. `decode` turns the bytes into a value, and
		loads through its `AssetContext` the other assets that the value holds.
		`close` releases what the value holds outside the heap, such as a GPU
		texture.
	**/
	public function new(name:String, decode:(Bytes, AssetContext) -> Future<T>, ?close:T->Void) {
		this.name = name;
		decoder = decode;
		closer = close;
	}

	@:allow(hxn.me) function decode(bytes:Bytes, context:AssetContext):Future<T>
		return decoder(bytes, context);

	@:allow(hxn.me) function close(value:T):Void
		if (closer != null)
			closer(value);
}
