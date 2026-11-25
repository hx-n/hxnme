package hxn.me.dev;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;

/** `Update` is what `hxn me dev` sends to the running app after a change. **/
@:noCompletion
class Update {
	/** `code` is true if the app has new code to load. **/
	public final code:Bool;

	/** `files` holds the asset files that changed, by their path in the bundled assets. **/
	public final files:Map<String, Bytes>;

	public function new(code:Bool, files:Map<String, Bytes>) {
		this.code = code;
		this.files = files;
	}

	/** Returns the update as bytes, for `read`. **/
	public function write():Bytes {
		var out = new BytesOutput();
		out.writeByte(code ? 1 : 0);
		for (path => bytes in files) {
			var name = Bytes.ofString(path);
			out.writeInt32(name.length);
			out.write(name);
			out.writeInt32(bytes.length);
			out.write(bytes);
		}
		return out.getBytes();
	}

	/** Returns the update that `write` made `bytes` from. **/
	public static function read(bytes:Bytes):Update {
		var input = new BytesInput(bytes);
		var code = input.readByte() == 1;
		var files = new Map<String, Bytes>();
		while (input.position < input.length) {
			var path = input.readString(input.readInt32());
			files.set(path, input.read(input.readInt32()));
		}
		return new Update(code, files);
	}
}
