package hxn.me.math;

/** Symmetric 3x3 tensor. */
class Mat3 {
	public var xx:Single;
	public var yy:Single;
	public var zz:Single;
	public var xy:Single;
	public var xz:Single;
	public var yz:Single;

	public inline function new(xx:Single = 0.0, yy:Single = 0.0, zz:Single = 0.0, xy:Single = 0.0, xz:Single = 0.0, yz:Single = 0.0) {
		this.xx = xx;
		this.yy = yy;
		this.zz = zz;
		this.xy = xy;
		this.xz = xz;
		this.yz = yz;
	}

	public function inverse():Mat3 {
		var scale = Math.max(Math.abs(xx), Math.max(Math.abs(yy), Math.abs(zz)));
		if (scale <= 0.0)
			return new Mat3();
		var det = xx * (yy * zz - yz * yz) - xy * (xy * zz - yz * xz) + xz * (xy * yz - yy * xz);
		if (det <= 1e-12 * scale * scale * scale)
			return new Mat3();
		var inv = 1.0 / det;
		return new Mat3((yy * zz - yz * yz) * inv, (xx * zz - xz * xz) * inv, (xx * yy - xy * xy) * inv, (xz * yz - xy * zz) * inv, (xy * yz - xz * yy) * inv,
			(xy * xz - xx * yz) * inv);
	}

	public static inline function rotatedDiagonal(q:Quat, ix:Single, iy:Single, iz:Single):Mat3 {
		return rotated(q, new Mat3(ix, iy, iz));
	}

	public static function rotated(q:Quat, m:Mat3):Mat3 {
		var x = q.x, y = q.y, z = q.z, w = q.w;
		var r00 = 1.0 - 2.0 * (y * y + z * z);
		var r01 = 2.0 * (x * y - z * w);
		var r02 = 2.0 * (x * z + y * w);
		var r10 = 2.0 * (x * y + z * w);
		var r11 = 1.0 - 2.0 * (x * x + z * z);
		var r12 = 2.0 * (y * z - x * w);
		var r20 = 2.0 * (x * z - y * w);
		var r21 = 2.0 * (y * z + x * w);
		var r22 = 1.0 - 2.0 * (x * x + y * y);
		var t00 = r00 * m.xx + r01 * m.xy + r02 * m.xz;
		var t01 = r00 * m.xy + r01 * m.yy + r02 * m.yz;
		var t02 = r00 * m.xz + r01 * m.yz + r02 * m.zz;
		var t10 = r10 * m.xx + r11 * m.xy + r12 * m.xz;
		var t11 = r10 * m.xy + r11 * m.yy + r12 * m.yz;
		var t12 = r10 * m.xz + r11 * m.yz + r12 * m.zz;
		var t20 = r20 * m.xx + r21 * m.xy + r22 * m.xz;
		var t21 = r20 * m.xy + r21 * m.yy + r22 * m.yz;
		var t22 = r20 * m.xz + r21 * m.yz + r22 * m.zz;
		return new Mat3(t00 * r00
			+ t01 * r01
			+ t02 * r02, t10 * r10
			+ t11 * r11
			+ t12 * r12, t20 * r20
			+ t21 * r21
			+ t22 * r22,
			t00 * r10
			+ t01 * r11
			+ t02 * r12, t00 * r20
			+ t01 * r21
			+ t02 * r22, t10 * r20
			+ t11 * r21
			+ t12 * r22);
	}

	public inline function multiply(v:Vec3):Vec3 {
		return new Vec3(xx * v.x + xy * v.y + xz * v.z, xy * v.x + yy * v.y + yz * v.z, xz * v.x + yz * v.y + zz * v.z);
	}
}
