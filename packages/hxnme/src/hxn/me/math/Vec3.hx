package hxn.me.math;

class Vec3 {
	public var x:Single;
	public var y:Single;
	public var z:Single;

	public inline function new(x:Single = 0.0, y:Single = 0.0, z:Single = 0.0) {
		this.x = x;
		this.y = y;
		this.z = z;
	}

	public static inline function dot(a:Vec3, b:Vec3):Single {
		return a.x * b.x + a.y * b.y + a.z * b.z;
	}

	public static inline function cross(a:Vec3, b:Vec3):Vec3 {
		return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
	}

	public static inline function sub(a:Vec3, b:Vec3):Vec3 {
		return new Vec3(a.x - b.x, a.y - b.y, a.z - b.z);
	}

	public static inline function add(a:Vec3, b:Vec3):Vec3 {
		return new Vec3(a.x + b.x, a.y + b.y, a.z + b.z);
	}

	public static inline function scale(a:Vec3, s:Single):Vec3 {
		return new Vec3(a.x * s, a.y * s, a.z * s);
	}

	public static inline function madd(a:Vec3, b:Vec3, s:Single):Vec3 {
		return new Vec3(a.x + b.x * s, a.y + b.y * s, a.z + b.z * s);
	}

	public static inline function lengthSq(a:Vec3):Single {
		return a.x * a.x + a.y * a.y + a.z * a.z;
	}

	public static inline function normalize(a:Vec3):Vec3 {
		var lenSq = lengthSq(a);
		if (lenSq < 1e-12)
			return new Vec3(0.0, 1.0, 0.0);
		var inv:Single = 1.0 / Math.sqrt(lenSq);
		return new Vec3(a.x * inv, a.y * inv, a.z * inv);
	}
}
