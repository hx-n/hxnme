package hxn.me.math;

import hxn.Float32Buffer;
import hxn.Int32Buffer;

/** Larger copies of the storage a physics world keeps by body, shape or joint, for when it is given more room. */
// Haxe Int arithmetic wraps on overflow. -fwrapv gives the generated C++ the
// same meaning on clang and gcc; without it, signed overflow is undefined and
// the optimizer can drop masks and comparisons that depend on wrapping.
// Haxe rounds the result of each Float and Single operation, as HashLink does.
// -ffp-contract=off stops clang and gcc from fusing a multiply and an add into
// one rounding, so hxcpp computes the same bits as HashLink.
// Under Emscripten the heap has a fixed size unless it is allowed to grow,
// and the storage grows here.
#if cpp
@:buildXml('<files id="haxe"><compilerflag value="-fwrapv" unless="isMsvc"/><compilerflag value="-ffp-contract=off" unless="isMsvc"/></files>
<linker id="exe" if="emscripten"><flag value="-sALLOW_MEMORY_GROWTH=1"/></linker>')
#end
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
