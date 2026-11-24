package hxn.me.math;

/**
	`Float32Bytes` stores 32-bit floats that code addresses by byte offset. It
	holds records whose fields have fixed offsets, and that code reads four
	lanes at a time. Offsets are multiples of 4. On HashLink and Ash it is
	`hl.Bytes`, so `ash.simd` loads and stores read it directly.
**/
abstract Float32Bytes(#if hl hl.Bytes #else Array<Single> #end) #if hl to hl.Bytes #end {
	/** Makes storage for `byteLength` bytes. **/
	public inline function new(byteLength:Int) {
		#if hl
		this = new hl.Bytes(byteLength);
		#elseif cpp
		this = cpp.NativeArray.create(byteLength >> 2);
		#else
		this = [for (_ in 0...byteLength >> 2) 0.0];
		#end
	}

	public inline function getF32(offset:Int):Single {
		#if hl
		return this.getF32(offset);
		#elseif (cpp && !cppia)
		return cpp.NativeArray.unsafeGet(this, offset >> 2);
		#else
		return this[offset >> 2];
		#end
	}

	public inline function setF32(offset:Int, value:Single):Void {
		#if hl
		this.setF32(offset, value);
		#elseif (cpp && !cppia)
		cpp.NativeArray.unsafeSet(this, offset >> 2, value);
		#else
		this[offset >> 2] = value;
		#end
	}

	/** Sets the `length` bytes from `offset` to zero. **/
	public inline function clear(offset:Int, length:Int):Void {
		#if hl
		this.fill(offset, length, 0);
		#else
		for (i in offset >> 2...(offset + length) >> 2)
			this[i] = 0.0;
		#end
	}

	/** Copies `length` bytes of `source`, from `sourceOffset`, to `offset`. **/
	public inline function blit(offset:Int, source:Float32Bytes, sourceOffset:Int, length:Int):Void {
		#if hl
		this.blit(offset, source, sourceOffset, length);
		#elseif (cpp && !cppia)
		cpp.NativeArray.blit(this, offset >> 2, cast source, sourceOffset >> 2, length >> 2);
		#else
		var from:Array<Single> = cast source;
		for (i in 0...length >> 2)
			this[(offset >> 2) + i] = from[(sourceOffset >> 2) + i];
		#end
	}
}
