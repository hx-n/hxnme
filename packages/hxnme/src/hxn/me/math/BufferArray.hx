package hxn.me.math;

/**
	A fixed-length array of typed buffers, such as `hxn.Float32Buffer`. It holds
	the buffers without boxing them: `hl.NativeArray` on HashLink and Ash, and
	`haxe.ds.Vector` on the other runtimes.
**/
typedef BufferArray<T> = #if hl hl.NativeArray<T> #else haxe.ds.Vector<T> #end;
