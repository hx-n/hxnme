package hxn.me.render2d;

import haxe.io.Bytes;

/**
	`Instances` stores the instances of the 2D shader as structure of arrays:
	one array of four floats for each field, in the order of `Shader`'s
	inputs. Each array becomes one per-instance vertex buffer, so a change to
	one field uploads only that field.
**/
class Instances {
	/** The number of fields, each four floats. **/
	public static inline final FIELDS = 7;

	public static inline final RECT = 0;
	public static inline final UV = 1;
	public static inline final COLOR = 2;
	public static inline final XFORM = 3;
	public static inline final SHAPE = 4;
	public static inline final RADIUS = 5;
	public static inline final BORDER = 6;

	/** The bytes of one field of one instance. **/
	public static inline final STRIDE = 16;

	public final fields:Array<Bytes> = [];
	public var length(default, null) = 0;
	public var capacity(default, null):Int;

	public function new(capacity = 256) {
		this.capacity = capacity;
		for (_ in 0...FIELDS)
			fields.push(Bytes.alloc(capacity * STRIDE));
	}

	/** Adds an instance with every field zero, and returns its index. **/
	public function add():Int {
		if (length == capacity)
			grow(capacity * 2);
		for (f in fields)
			f.fill(length * STRIDE, STRIDE, 0);
		return length++;
	}

	public function clear():Void
		length = 0;

	public inline function set(field:Int, index:Int, a:Float, b:Float, c:Float, d:Float):Void {
		var bytes = fields[field];
		var at = index * STRIDE;
		bytes.setFloat(at, a);
		bytes.setFloat(at + 4, b);
		bytes.setFloat(at + 8, c);
		bytes.setFloat(at + 12, d);
	}

	function grow(to:Int):Void {
		for (i in 0...FIELDS) {
			var bigger = Bytes.alloc(to * STRIDE);
			bigger.blit(0, fields[i], 0, length * STRIDE);
			fields[i] = bigger;
		}
		capacity = to;
	}
}
