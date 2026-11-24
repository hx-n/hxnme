package hxn.me.math;

/**
	`BufferArray` holds a fixed number of typed buffers, such as
	`hxn.Float32Buffer`, without boxing them. It is `hl.NativeArray` on
	HashLink and Ash, and `haxe.ds.Vector` on the other runtimes.
**/
typedef BufferArray<T> = #if hl hl.NativeArray<T> #else haxe.ds.Vector<T> #end;
