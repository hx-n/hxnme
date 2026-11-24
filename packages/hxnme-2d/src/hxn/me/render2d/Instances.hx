package hxn.me.render2d;

import haxe.io.Bytes;

/**
	`Instances` stores the instances of the 2D shader as a structure of arrays.
	Each field, such as `RECT` or `COLOR`, has its own array with four values
	for each instance, in the order of the inputs of `Shader`. The colors
	`COLOR` and `BORDER` take one byte for each value, which the GPU reads as 0
	to 1, and the other fields take four floats. Each array becomes one
	per-instance vertex buffer, so a change to one field uploads only that
	field.
**/
class Instances {
	/** The number of fields. Each field holds four values. **/
	public static inline final FIELDS = 7;

	public static inline final RECT = 0;
	public static inline final UV = 1;
	public static inline final COLOR = 2;
	public static inline final XFORM = 3;
	public static inline final SHAPE = 4;
	public static inline final RADIUS = 5;
	public static inline final BORDER = 6;

	/** The bytes of all the fields of one instance. **/
	public static inline final BYTES = 5 * 16 + 2 * 4;

	/** Returns whether `field` holds a color, packed in four bytes. **/
	public static inline function packed(field:Int):Bool
		return field == COLOR || field == BORDER;

	/** Returns the bytes of `field` for one instance. **/
	public static inline function stride(field:Int):Int
		return packed(field) ? 4 : 16;

	public final fields:Array<Bytes> = [];
	public var length(default, null) = 0;
	public var capacity(default, null):Int;

	public function new(capacity = 256) {
		this.capacity = capacity;
		for (field in 0...FIELDS)
			fields.push(Bytes.alloc(capacity * stride(field)));
	}

	/** Adds an instance with every field zero, and returns its index. **/
	public function add():Int {
		if (length == capacity)
			grow(capacity * 2);
		for (field in 0...FIELDS)
			fields[field].fill(length * stride(field), stride(field), 0);
		return length++;
	}

	public function clear():Void
		length = 0;

	/** Writes the four values of `field` of instance `index`. A color's values are from 0 to 1. **/
	public inline function set(field:Int, index:Int, a:Float, b:Float, c:Float, d:Float):Void {
		var bytes = fields[field];
		if (packed(field)) {
			var at = index * 4;
			bytes.set(at, unit(a));
			bytes.set(at + 1, unit(b));
			bytes.set(at + 2, unit(c));
			bytes.set(at + 3, unit(d));
		} else {
			var at = index * 16;
			bytes.setFloat(at, a);
			bytes.setFloat(at + 4, b);
			bytes.setFloat(at + 8, c);
			bytes.setFloat(at + 12, d);
		}
	}

	// Returns `v`, from 0 to 1, as a byte from 0 to 255.
	static inline function unit(v:Float):Int
		return v <= 0 ? 0 : v >= 1 ? 255 : Math.round(v * 255);

	/** Writes `a` and `b` into `field` of instance `index`, from value `at` of the four. `field` is not a color. **/
	public inline function setPair(field:Int, index:Int, at:Int, a:Float, b:Float):Void {
		var bytes = fields[field];
		var offset = index * 16 + at * 4;
		bytes.setFloat(offset, a);
		bytes.setFloat(offset + 4, b);
	}

	/** Returns value `at` of `field` of instance `index`. A color's values are from 0 to 1. **/
	public inline function get(field:Int, index:Int, at:Int):Float
		return packed(field) ? fields[field].get(index * 4 + at) / 255 : fields[field].getFloat(index * 16 + at * 4);

	/** Copies every field of instance `from` over instance `to`. **/
	public function copy(from:Int, to:Int):Void
		for (field in 0...FIELDS) {
			var f = fields[field], size = stride(field);
			f.blit(to * size, f, from * size, size);
		}

	/** Removes the last instance. **/
	public function pop():Void
		length--;

	function grow(to:Int):Void {
		for (i in 0...FIELDS) {
			var bigger = Bytes.alloc(to * stride(i));
			bigger.blit(0, fields[i], 0, length * stride(i));
			fields[i] = bigger;
		}
		capacity = to;
	}
}
