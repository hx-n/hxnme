package hxn.me.math;

import hxn.Float32Buffer;
import hxn.Int32Buffer;

/** Larger copies of the storage a physics world keeps by body, shape or joint, for when it is given more room. */
class Grow {
	/** `a` with room for `to` entries: the first `from` kept, the rest `fill`. */
	public static function ints(a:Int32Buffer, from:Int, to:Int, fill:Int = 0):Int32Buffer {
		var b = new Int32Buffer(to);
		b.blit(0, a, 0, from);
		if (fill != 0)
			for (i in from...to)
				b[i] = fill;
		return b;
	}

	public static function singles(a:Float32Buffer, from:Int, to:Int):Float32Buffer {
		var b = new Float32Buffer(to);
		b.blit(0, a, 0, from);
		return b;
	}

	public static function floats(a:Float32Buffer, from:Int, to:Int):Float32Buffer {
		var b = new Float32Buffer(to);
		b.blit(0, a, 0, from);
		return b;
	}
}
