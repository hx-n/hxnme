package hxn.me.physics.joints;

import hxn.me.math.Grow;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.Float32Buffer;
import hxn.me.physics.core.Handles.DoFMask;

class PrismaticSolver {
	var pool:JointPool;
	var localAxisAX:Float32Buffer;
	var localAxisAY:Float32Buffer;
	var localAxisAZ:Float32Buffer;
	var localAxisBX:Float32Buffer;
	var localAxisBY:Float32Buffer;
	var localAxisBZ:Float32Buffer;
	var localRefAX:Float32Buffer;
	var localRefAY:Float32Buffer;
	var localRefAZ:Float32Buffer;
	var localRefBX:Float32Buffer;
	var localRefBY:Float32Buffer;
	var localRefBZ:Float32Buffer;
	var axisAX:Float32Buffer;
	var axisAY:Float32Buffer;
	var axisAZ:Float32Buffer;
	var axisBX:Float32Buffer;
	var axisBY:Float32Buffer;
	var axisBZ:Float32Buffer;
	var refAX:Float32Buffer;
	var refAY:Float32Buffer;
	var refAZ:Float32Buffer;
	var refBX:Float32Buffer;
	var refBY:Float32Buffer;
	var refBZ:Float32Buffer;
	var transverseImpulse1:Float32Buffer;
	var transverseImpulse2:Float32Buffer;
	var tiltImpulse1:Float32Buffer;
	var tiltImpulse2:Float32Buffer;
	var twistImpulse:Float32Buffer;
	var limitState:hxn.Int32Buffer;
	var limitImpulse:Float32Buffer;
	var motorImpulse:Float32Buffer;
	var lowerTranslation:Float32Buffer;
	var upperTranslation:Float32Buffer;
	var motorSpeed:Float32Buffer;
	var maxMotorForce:Float32Buffer;

	public function new(pool:JointPool, capacity:Int) {
		this.pool = pool;
		localAxisAX = new Float32Buffer(capacity);
		localAxisAY = new Float32Buffer(capacity);
		localAxisAZ = new Float32Buffer(capacity);
		localAxisBX = new Float32Buffer(capacity);
		localAxisBY = new Float32Buffer(capacity);
		localAxisBZ = new Float32Buffer(capacity);
		localRefAX = new Float32Buffer(capacity);
		localRefAY = new Float32Buffer(capacity);
		localRefAZ = new Float32Buffer(capacity);
		localRefBX = new Float32Buffer(capacity);
		localRefBY = new Float32Buffer(capacity);
		localRefBZ = new Float32Buffer(capacity);
		axisAX = new Float32Buffer(capacity);
		axisAY = new Float32Buffer(capacity);
		axisAZ = new Float32Buffer(capacity);
		axisBX = new Float32Buffer(capacity);
		axisBY = new Float32Buffer(capacity);
		axisBZ = new Float32Buffer(capacity);
		refAX = new Float32Buffer(capacity);
		refAY = new Float32Buffer(capacity);
		refAZ = new Float32Buffer(capacity);
		refBX = new Float32Buffer(capacity);
		refBY = new Float32Buffer(capacity);
		refBZ = new Float32Buffer(capacity);
		transverseImpulse1 = new Float32Buffer(capacity);
		transverseImpulse2 = new Float32Buffer(capacity);
		tiltImpulse1 = new Float32Buffer(capacity);
		tiltImpulse2 = new Float32Buffer(capacity);
		twistImpulse = new Float32Buffer(capacity);
		limitState = new hxn.Int32Buffer(capacity);
		limitImpulse = new Float32Buffer(capacity);
		motorImpulse = new Float32Buffer(capacity);
		lowerTranslation = new Float32Buffer(capacity);
		upperTranslation = new Float32Buffer(capacity);
		motorSpeed = new Float32Buffer(capacity);
		maxMotorForce = new Float32Buffer(capacity);
	}

	/** Makes room for `to` joints, and keeps the first `from`. */
	public function grow(from:Int, to:Int):Void {
		localAxisAX = Grow.floats(localAxisAX, from, to);
		localAxisAY = Grow.floats(localAxisAY, from, to);
		localAxisAZ = Grow.floats(localAxisAZ, from, to);
		localAxisBX = Grow.floats(localAxisBX, from, to);
		localAxisBY = Grow.floats(localAxisBY, from, to);
		localAxisBZ = Grow.floats(localAxisBZ, from, to);
		localRefAX = Grow.floats(localRefAX, from, to);
		localRefAY = Grow.floats(localRefAY, from, to);
		localRefAZ = Grow.floats(localRefAZ, from, to);
		localRefBX = Grow.floats(localRefBX, from, to);
		localRefBY = Grow.floats(localRefBY, from, to);
		localRefBZ = Grow.floats(localRefBZ, from, to);
		axisAX = Grow.floats(axisAX, from, to);
		axisAY = Grow.floats(axisAY, from, to);
		axisAZ = Grow.floats(axisAZ, from, to);
		axisBX = Grow.floats(axisBX, from, to);
		axisBY = Grow.floats(axisBY, from, to);
		axisBZ = Grow.floats(axisBZ, from, to);
		refAX = Grow.floats(refAX, from, to);
		refAY = Grow.floats(refAY, from, to);
		refAZ = Grow.floats(refAZ, from, to);
		refBX = Grow.floats(refBX, from, to);
		refBY = Grow.floats(refBY, from, to);
		refBZ = Grow.floats(refBZ, from, to);
		transverseImpulse1 = Grow.floats(transverseImpulse1, from, to);
		transverseImpulse2 = Grow.floats(transverseImpulse2, from, to);
		tiltImpulse1 = Grow.floats(tiltImpulse1, from, to);
		tiltImpulse2 = Grow.floats(tiltImpulse2, from, to);
		twistImpulse = Grow.floats(twistImpulse, from, to);
		limitState = Grow.ints(limitState, from, to);
		limitImpulse = Grow.floats(limitImpulse, from, to);
		motorImpulse = Grow.floats(motorImpulse, from, to);
		lowerTranslation = Grow.floats(lowerTranslation, from, to);
		upperTranslation = Grow.floats(upperTranslation, from, to);
		motorSpeed = Grow.floats(motorSpeed, from, to);
		maxMotorForce = Grow.floats(maxMotorForce, from, to);
	}


	public function initialize(id:Int, qa:Quat, qb:Quat, axis:Vec3, lower:Single, upper:Single, speed:Single, force:Single):Void {
		var reference = Math.abs(axis.z) > 0.9 ? new Vec3(1, 0, 0) : new Vec3(0, 0, 1);
		reference = Vec3.normalize(Vec3.cross(axis, reference));
		var aa = Quat.invRotate(qa, axis), ab = Quat.invRotate(qb, axis);
		var ra = Quat.invRotate(qa, reference),
			rb = Quat.invRotate(qb, reference);
		localAxisAX[id] = aa.x;
		localAxisAY[id] = aa.y;
		localAxisAZ[id] = aa.z;
		localAxisBX[id] = ab.x;
		localAxisBY[id] = ab.y;
		localAxisBZ[id] = ab.z;
		localRefAX[id] = ra.x;
		localRefAY[id] = ra.y;
		localRefAZ[id] = ra.z;
		localRefBX[id] = rb.x;
		localRefBY[id] = rb.y;
		localRefBZ[id] = rb.z;
		lowerTranslation[id] = lower;
		upperTranslation[id] = upper;
		motorSpeed[id] = speed;
		maxMotorForce[id] = force;
		transverseImpulse1[id] = transverseImpulse2[id] = 0.0;
		tiltImpulse1[id] = tiltImpulse2[id] = twistImpulse[id] = 0.0;
		limitImpulse[id] = motorImpulse[id] = 0.0;
		limitState[id] = 0;
	}

	inline function positionBias(error:Float, h:Single):Single {
		var correction = Math.max(0.0, Math.abs(error) - 0.001);
		return Math.max(-10.0, Math.min(10.0, 0.2 * (error < 0.0 ? -correction : correction) / h));
	}

	/** Emits transverse and tilt rows, the twist row, then the axial limit and motor rows. */
	public function prepare(id:Int, dx:Float, dy:Float, dz:Float, h:Single):Void {
		var world = pool.world, rows = pool.rows;
		var a = pool.bodyA[id], b = pool.bodyB[id];
		var spatial = world.bodyDoF[a] == DoFMask.Full3D || world.bodyDoF[b] == DoFMask.Full3D;
		rotateInto(a, localAxisAX[id], localAxisAY[id], localAxisAZ[id], axisAX, axisAY, axisAZ, id);
		rotateInto(b, localAxisBX[id], localAxisBY[id], localAxisBZ[id], axisBX, axisBY, axisBZ, id);
		rotateInto(a, localRefAX[id], localRefAY[id], localRefAZ[id], refAX, refAY, refAZ, id);
		rotateInto(b, localRefBX[id], localRefBY[id], localRefBZ[id], refBX, refBY, refBZ, id);
		var ax = axisAX[id], ay = axisAY[id], az = axisAZ[id];
		var bx = axisBX[id], by = axisBY[id], bz = axisBZ[id];
		var t1x = 0.0, t1y = 0.0, t1z = 0.0;
		if (ax * ax + ay * ay > az * az) {
			var inv = 1.0 / Math.sqrt(ax * ax + ay * ay);
			t1x = -ay * inv;
			t1y = ax * inv;
		} else {
			var inv = 1.0 / Math.sqrt(ay * ay + az * az);
			t1y = -az * inv;
			t1z = ay * inv;
		}
		var t2x = ay * t1z - az * t1y,
			t2y = az * t1x - ax * t1z,
			t2z = ax * t1y - ay * t1x;
		// The guide axis turns with A, so A's lever arm reaches B's anchor.
		var rax = pool.rAX[id] + dx,
			ray = pool.rAY[id] + dy,
			raz = pool.rAZ[id] + dz;
		var rbx:Float = pool.rBX[id],
			rby:Float = pool.rBY[id],
			rbz:Float = pool.rBZ[id];
		var k = rows.linear(t1x, t1y, t1z, rax, ray, raz, rbx, rby, rbz);
		rows.setEquality(k > 0.0 ? 1.0 / k : 0.0, positionBias(dx * t1x + dy * t1y + dz * t1z, h), 0.0, transverseImpulse1, id);
		if (spatial) {
			k = rows.linear(t2x, t2y, t2z, rax, ray, raz, rbx, rby, rbz);
			rows.setEquality(k > 0.0 ? 1.0 / k : 0.0, positionBias(dx * t2x + dy * t2y + dz * t2z, h), 0.0, transverseImpulse2, id);
			var ex = ay * bz - az * by,
				ey = az * bx - ax * bz,
				ez = ax * by - ay * bx;
			k = rows.angular(t1x, t1y, t1z);
			rows.setEquality(k > 0.0 ? 1.0 / k : 0.0, positionBias(ex * t1x + ey * t1y + ez * t1z, h), 0.0, tiltImpulse1, id);
			k = rows.angular(t2x, t2y, t2z);
			rows.setEquality(k > 0.0 ? 1.0 / k : 0.0, positionBias(ex * t2x + ey * t2y + ez * t2z, h), 0.0, tiltImpulse2, id);
		} else {
			transverseImpulse2[id] = tiltImpulse1[id] = tiltImpulse2[id] = 0.0;
		}
		var rx = spatial ? ax : 0.0;
		var ry = spatial ? ay : 0.0;
		var rz = spatial ? az : 1.0;
		var refax = refAX[id], refay = refAY[id], refaz = refAZ[id];
		var refbx = refBX[id], refby = refBY[id], refbz = refBZ[id];
		var sine = rx * (refay * refbz - refaz * refby) + ry * (refaz * refbx - refax * refbz) + rz * (refax * refby - refay * refbx);
		var angle = Math.atan2(sine, refax * refbx + refay * refby + refaz * refbz);
		k = rows.angular(rx, ry, rz);
		rows.setEquality(k > 0.0 ? 1.0 / k : 0.0, positionBias(angle, h), 0.0, twistImpulse, id);
		var translation = dx * ax + dy * ay + dz * az;
		var state = translation < lowerTranslation[id] ? 1 : (translation > upperTranslation[id] ? -1 : 0);
		if (state != limitState[id])
			limitImpulse[id] = 0.0;
		limitState[id] = state;
		var maxImpulse = maxMotorForce[id] * h;
		motorImpulse[id] = Math.max(-maxImpulse, Math.min(maxImpulse, motorImpulse[id]));
		// When a motor pushes into an active limit, the limit row handles it.
		var blocked = state == 1 && motorSpeed[id] < 0.0 || state == -1 && motorSpeed[id] > 0.0;
		if (blocked)
			motorImpulse[id] = 0.0;
		if (state != 0) {
			k = rows.linear(ax, ay, az, rax, ray, raz, rbx, rby, rbz);
			var mass = k > 0.0 ? 1.0 / k : 0.0;
			var bias = positionBias(translation - (state == 1 ? lowerTranslation[id] : upperTranslation[id]), h);
			rows.set(-mass * bias, mass, 0.0, state == 1 ? 0.0 : Math.NEGATIVE_INFINITY, state == 1 ? Math.POSITIVE_INFINITY : 0.0, limitImpulse, id);
			rows.relaxWithout();
		}
		if (maxImpulse > 0.0 && !blocked) {
			k = rows.linear(ax, ay, az, rax, ray, raz, rbx, rby, rbz);
			var mass = k > 0.0 ? 1.0 / k : 0.0;
			rows.set(mass * motorSpeed[id], mass, 0.0, -maxImpulse, maxImpulse, motorImpulse, id);
		}
	}

	function rotateInto(body:Int, lx:Float, ly:Float, lz:Float, outX:Float32Buffer, outY:Float32Buffer, outZ:Float32Buffer, id:Int):Void {
		var world = pool.world;
		var qx = world.rotX[body],
			qy = world.rotY[body],
			qz = world.rotZ[body],
			qw = world.rotW[body];
		var tx = 2.0 * (qy * lz - qz * ly),
			ty = 2.0 * (qz * lx - qx * lz),
			tz = 2.0 * (qx * ly - qy * lx);
		outX[id] = lx + qw * tx + qy * tz - qz * ty;
		outY[id] = ly + qw * ty + qz * tx - qx * tz;
		outZ[id] = lz + qw * tz + qx * ty - qy * tx;
	}

	/** Visits settings and warm starts for `WorldSnapshot`. Each substep rebuilds the world-space axes. */
	@:noCompletion public function visitState(s:hxn.me.physics.core.WorldSnapshot, joints:Int):Void {
		s.floats(localAxisAX, joints);
		s.floats(localAxisAY, joints);
		s.floats(localAxisAZ, joints);
		s.floats(localAxisBX, joints);
		s.floats(localAxisBY, joints);
		s.floats(localAxisBZ, joints);
		s.floats(localRefAX, joints);
		s.floats(localRefAY, joints);
		s.floats(localRefAZ, joints);
		s.floats(localRefBX, joints);
		s.floats(localRefBY, joints);
		s.floats(localRefBZ, joints);
		s.floats(transverseImpulse1, joints);
		s.floats(transverseImpulse2, joints);
		s.floats(tiltImpulse1, joints);
		s.floats(tiltImpulse2, joints);
		s.floats(twistImpulse, joints);
		s.floats(limitImpulse, joints);
		s.floats(motorImpulse, joints);
		s.floats(lowerTranslation, joints);
		s.floats(upperTranslation, joints);
		s.floats(motorSpeed, joints);
		s.floats(maxMotorForce, joints);
		s.ints(limitState, joints);
	}
}
