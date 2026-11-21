package hxn.me.math;

import hxn.me.math.Simd.FloatBuffer;
import hl.NativeArray;

/** Larger copies of the storage a physics world keeps by body, shape or joint, for when it is given more room. */
class Grow {
	/** `a` with room for `to` entries: the first `from` kept, the rest `fill`. */
	public static function ints(a:NativeArray<Int>, from:Int, to:Int, fill:Int = 0):NativeArray<Int> {
		var b = new NativeArray<Int>(to);
		b.blit(0, a, 0, from);
		if (fill != 0)
			for (i in from...to)
				b[i] = fill;
		return b;
	}

	public static function singles(a:NativeArray<Single>, from:Int, to:Int):NativeArray<Single> {
		var b = new NativeArray<Single>(to);
		b.blit(0, a, 0, from);
		return b;
	}

	public static function floats(a:FloatBuffer, from:Int, to:Int):FloatBuffer {
		var b = new FloatBuffer(to);
		(b : hl.Bytes).blit(0, (a : hl.Bytes), 0, from << 2);
		return b;
	}
}
