package hxn.me.math;

class Quat {
	public var x:Single;
	public var y:Single;
	public var z:Single;
	public var w:Single;

	public inline function new(x:Single = 0.0, y:Single = 0.0, z:Single = 0.0, w:Single = 1.0) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = w;
	}

	public static inline function rotate(q:Quat, v:Vec3):Vec3 {
		var tx:Single = 2.0 * (q.y * v.z - q.z * v.y);
		var ty:Single = 2.0 * (q.z * v.x - q.x * v.z);
		var tz:Single = 2.0 * (q.x * v.y - q.y * v.x);
		return new Vec3(v.x + q.w * tx + (q.y * tz - q.z * ty), v.y + q.w * ty + (q.z * tx - q.x * tz), v.z + q.w * tz + (q.x * ty - q.y * tx));
	}

	public static inline function invRotate(q:Quat, v:Vec3):Vec3 {
		var tx:Single = 2.0 * (q.z * v.y - q.y * v.z);
		var ty:Single = 2.0 * (q.x * v.z - q.z * v.x);
		var tz:Single = 2.0 * (q.y * v.x - q.x * v.y);
		return new Vec3(v.x + q.w * tx + (q.z * ty - q.y * tz), v.y + q.w * ty + (q.x * tz - q.z * tx), v.z + q.w * tz + (q.y * tx - q.x * ty));
	}

	public static function integrate(q:Quat, omega:Vec3, dt:Single):Quat {
		var half:Single = 0.5 * dt;
		var x:Single = q.x + half * (omega.x * q.w + omega.y * q.z - omega.z * q.y);
		var y:Single = q.y + half * (omega.y * q.w + omega.z * q.x - omega.x * q.z);
		var z:Single = q.z + half * (omega.z * q.w + omega.x * q.y - omega.y * q.x);
		var w:Single = q.w - half * (omega.x * q.x + omega.y * q.y + omega.z * q.z);
		var n:Single = 1.0 / Math.sqrt(x * x + y * y + z * z + w * w);
		return new Quat(x * n, y * n, z * n, w * n);
	}

	public static function slerp(a:Quat, b:Quat, t:Single):Quat {
		var dot:Float = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
		var sign:Single = dot < 0.0 ? -1.0 : 1.0;
		if (dot < 0.0)
			dot = -dot;
		var wa:Float, wb:Float;
		if (dot > 0.9995) {
			wa = 1.0 - t;
			wb = t;
		} else {
			var angle = Math.acos(Math.min(1.0, dot));
			var inverse = 1.0 / Math.sin(angle);
			wa = Math.sin((1.0 - t) * angle) * inverse;
			wb = Math.sin(t * angle) * inverse;
		}
		var x:Single = wa * a.x + wb * sign * b.x;
		var y:Single = wa * a.y + wb * sign * b.y;
		var z:Single = wa * a.z + wb * sign * b.z;
		var w:Single = wa * a.w + wb * sign * b.w;
		var inverseLength:Single = 1.0 / Math.sqrt(x * x + y * y + z * z + w * w);
		return new Quat(x * inverseLength, y * inverseLength, z * inverseLength, w * inverseLength);
	}

	public static function angularVelocity(start:Quat, target:Quat, dt:Single):Vec3 {
		var dot = start.x * target.x + start.y * target.y + start.z * target.z + start.w * target.w;
		var sign:Single = dot < 0.0 ? -1.0 : 1.0;
		var tx = target.x * sign,
			ty = target.y * sign,
			tz = target.z * sign,
			tw = target.w * sign;
		var x = tx * start.w - tw * start.x - ty * start.z + tz * start.y;
		var y = ty * start.w - tw * start.y - tz * start.x + tx * start.z;
		var z = tz * start.w - tw * start.z - tx * start.y + ty * start.x;
		var vectorLength = Math.sqrt(x * x + y * y + z * z);
		var scale = vectorLength < 1e-6 ? 2.0 / dt : 2.0 * Math.atan2(vectorLength, Math.max(0.0, dot * sign)) / (vectorLength * dt);
		return new Vec3(x * scale, y * scale, z * scale);
	}
}
