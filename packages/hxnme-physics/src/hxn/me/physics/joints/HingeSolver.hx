package hxn.me.physics.joints;

import hxn.me.math.Grow;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.math.Simd.FloatBuffer;
import hxn.me.physics.core.Handles.DoFMask;

class HingeSolver {
	var pool:JointPool;
	var localAxisAX:FloatBuffer;
	var localAxisAY:FloatBuffer;
	var localAxisAZ:FloatBuffer;
	var localAxisBX:FloatBuffer;
	var localAxisBY:FloatBuffer;
	var localAxisBZ:FloatBuffer;
	var localRefAX:FloatBuffer;
	var localRefAY:FloatBuffer;
	var localRefAZ:FloatBuffer;
	var localRefBX:FloatBuffer;
	var localRefBY:FloatBuffer;
	var localRefBZ:FloatBuffer;
	var axisAX:FloatBuffer;
	var axisAY:FloatBuffer;
	var axisAZ:FloatBuffer;
	var axisBX:FloatBuffer;
	var axisBY:FloatBuffer;
	var axisBZ:FloatBuffer;
	var refAX:FloatBuffer;
	var refAY:FloatBuffer;
	var refAZ:FloatBuffer;
	var refBX:FloatBuffer;
	var refBY:FloatBuffer;
	var refBZ:FloatBuffer;
	var pointImpulseX:FloatBuffer;
	var pointImpulseY:FloatBuffer;
	var pointImpulseZ:FloatBuffer;
	var tiltImpulse1:FloatBuffer;
	var tiltImpulse2:FloatBuffer;
	var limitState:hl.NativeArray<Int>;
	var limitImpulse:FloatBuffer;
	var motorImpulse:FloatBuffer;
	var lowerAngle:FloatBuffer;
	var upperAngle:FloatBuffer;
	var motorSpeed:FloatBuffer;
	var maxMotorTorque:FloatBuffer;
	var driveConfigured:hl.NativeArray<Int>;
	var driveTarget:FloatBuffer;
	var driveStiffness:FloatBuffer;
	var driveDamping:FloatBuffer;
	var driveTorque:FloatBuffer;

	public function new(pool:JointPool, capacity:Int) {
		this.pool = pool;
		localAxisAX = new FloatBuffer(capacity);
		localAxisAY = new FloatBuffer(capacity);
		localAxisAZ = new FloatBuffer(capacity);
		localAxisBX = new FloatBuffer(capacity);
		localAxisBY = new FloatBuffer(capacity);
		localAxisBZ = new FloatBuffer(capacity);
		localRefAX = new FloatBuffer(capacity);
		localRefAY = new FloatBuffer(capacity);
		localRefAZ = new FloatBuffer(capacity);
		localRefBX = new FloatBuffer(capacity);
		localRefBY = new FloatBuffer(capacity);
		localRefBZ = new FloatBuffer(capacity);
		axisAX = new FloatBuffer(capacity);
		axisAY = new FloatBuffer(capacity);
		axisAZ = new FloatBuffer(capacity);
		axisBX = new FloatBuffer(capacity);
		axisBY = new FloatBuffer(capacity);
		axisBZ = new FloatBuffer(capacity);
		refAX = new FloatBuffer(capacity);
		refAY = new FloatBuffer(capacity);
		refAZ = new FloatBuffer(capacity);
		refBX = new FloatBuffer(capacity);
		refBY = new FloatBuffer(capacity);
		refBZ = new FloatBuffer(capacity);
		pointImpulseX = new FloatBuffer(capacity);
		pointImpulseY = new FloatBuffer(capacity);
		pointImpulseZ = new FloatBuffer(capacity);
		tiltImpulse1 = new FloatBuffer(capacity);
		tiltImpulse2 = new FloatBuffer(capacity);
		limitState = new hl.NativeArray<Int>(capacity);
		limitImpulse = new FloatBuffer(capacity);
		motorImpulse = new FloatBuffer(capacity);
		lowerAngle = new FloatBuffer(capacity);
		upperAngle = new FloatBuffer(capacity);
		motorSpeed = new FloatBuffer(capacity);
		maxMotorTorque = new FloatBuffer(capacity);
		driveConfigured = new hl.NativeArray<Int>(capacity);
		driveTarget = new FloatBuffer(capacity);
		driveStiffness = new FloatBuffer(capacity);
		driveDamping = new FloatBuffer(capacity);
		driveTorque = new FloatBuffer(capacity);
	}

	/** Room for `to` joints, keeping the first `from`. */
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
		pointImpulseX = Grow.floats(pointImpulseX, from, to);
		pointImpulseY = Grow.floats(pointImpulseY, from, to);
		pointImpulseZ = Grow.floats(pointImpulseZ, from, to);
		tiltImpulse1 = Grow.floats(tiltImpulse1, from, to);
		tiltImpulse2 = Grow.floats(tiltImpulse2, from, to);
		limitState = Grow.ints(limitState, from, to);
		limitImpulse = Grow.floats(limitImpulse, from, to);
		motorImpulse = Grow.floats(motorImpulse, from, to);
		lowerAngle = Grow.floats(lowerAngle, from, to);
		upperAngle = Grow.floats(upperAngle, from, to);
		motorSpeed = Grow.floats(motorSpeed, from, to);
		maxMotorTorque = Grow.floats(maxMotorTorque, from, to);
		driveConfigured = Grow.ints(driveConfigured, from, to);
		driveTarget = Grow.floats(driveTarget, from, to);
		driveStiffness = Grow.floats(driveStiffness, from, to);
		driveDamping = Grow.floats(driveDamping, from, to);
		driveTorque = Grow.floats(driveTorque, from, to);
	}


	public function initialize(id:Int, qa:Quat, qb:Quat, axis:Vec3, lower:Single, upper:Single, speed:Single, torque:Single):Void {
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
		lowerAngle[id] = lower;
		upperAngle[id] = upper;
		motorSpeed[id] = speed;
		maxMotorTorque[id] = torque;
		pointImpulseX[id] = pointImpulseY[id] = pointImpulseZ[id] = 0.0;
		tiltImpulse1[id] = tiltImpulse2[id] = 0.0;
		limitImpulse[id] = motorImpulse[id] = 0.0;
		limitState[id] = 0;
		driveConfigured[id] = 0;
	}

	/**
	 * Reflects the joint's frames through the plane the diagonal reflection
	 * (ex, ey, ez) fixes, in each body's frame: axes reflect and reverse,
	 * references reflect, so the angle and its limits keep their values as the
	 * bodies' relative turn mirrors. Applying it twice restores the joint.
	 */
	public function mirror(id:Int, ex:Float, ey:Float, ez:Float):Void {
		localAxisAX[id] *= -ex;
		localAxisAY[id] *= -ey;
		localAxisAZ[id] *= -ez;
		localAxisBX[id] *= -ex;
		localAxisBY[id] *= -ey;
		localAxisBZ[id] *= -ez;
		localRefAX[id] *= ex;
		localRefAY[id] *= ey;
		localRefAZ[id] *= ez;
		localRefBX[id] *= ex;
		localRefBY[id] *= ey;
		localRefBZ[id] *= ez;
		pointImpulseX[id] = pointImpulseY[id] = pointImpulseZ[id] = 0.0;
		tiltImpulse1[id] = tiltImpulse2[id] = 0.0;
		limitImpulse[id] = motorImpulse[id] = 0.0;
		limitState[id] = 0;
	}

	public function setDrive(id:Int, target:Single, stiffness:Single, damping:Single, maxTorque:Single):Void {
		if (driveConfigured[id] == 0 || Math.abs(driveTarget[id] - target) > 0.6)
			motorImpulse[id] = 0.0;
		driveConfigured[id] = 1;
		driveTarget[id] = target;
		driveStiffness[id] = stiffness;
		driveDamping[id] = damping;
		driveTorque[id] = maxTorque;
	}

	inline function positionBias(error:Float, h:Single):Single {
		var correction = Math.max(0.0, Math.abs(error) - 0.001);
		return Math.max(-10.0, Math.min(10.0, 0.2 * (error < 0 ? -correction : correction) / h));
	}

	inline function pointRow(rows:JointRows, id:Int, x:Float, y:Float, z:Float, error:Float, h:Single, store:FloatBuffer):Void {
		var k = rows.linear(x, y, z, pool.rAX[id], pool.rAY[id], pool.rAZ[id], pool.rBX[id], pool.rBY[id], pool.rBZ[id]);
		rows.setEquality(k > 0.0 ? 1.0 / k : 0.0, positionBias(error, h), 0.0, store, id);
	}

	inline function tiltRow(rows:JointRows, id:Int, x:Float, y:Float, z:Float, error:Float, h:Single, store:FloatBuffer):Void {
		var k = rows.angular(x, y, z);
		rows.setEquality(k > 0.0 ? 1.0 / k : 0.0, positionBias(error, h), 0.0, store, id);
	}

	/** Emits anchor rows, tilt rows for 3D hinges, then the axial limit and motor rows. */
	public function prepare(id:Int, dx:Float, dy:Float, dz:Float, h:Single):Void {
		var world = pool.world, rows = pool.rows;
		var a = pool.bodyA[id], b = pool.bodyB[id];
		var spatial = world.bodyDoF[a] == DoFMask.Full3D || world.bodyDoF[b] == DoFMask.Full3D;
		pointRow(rows, id, 1, 0, 0, dx, h, pointImpulseX);
		pointRow(rows, id, 0, 1, 0, dy, h, pointImpulseY);
		if (spatial)
			pointRow(rows, id, 0, 0, 1, dz, h, pointImpulseZ);
		else
			pointImpulseZ[id] = 0.0;
		rotateInto(a, localAxisAX[id], localAxisAY[id], localAxisAZ[id], axisAX, axisAY, axisAZ, id);
		rotateInto(b, localAxisBX[id], localAxisBY[id], localAxisBZ[id], axisBX, axisBY, axisBZ, id);
		rotateInto(a, localRefAX[id], localRefAY[id], localRefAZ[id], refAX, refAY, refAZ, id);
		rotateInto(b, localRefBX[id], localRefBY[id], localRefBZ[id], refBX, refBY, refBZ, id);
		var ax = axisAX[id], ay = axisAY[id], az = axisAZ[id];
		var bx = axisBX[id], by = axisBY[id], bz = axisBZ[id];
		if (spatial) {
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
			var ex = ay * bz - az * by,
				ey = az * bx - ax * bz,
				ez = ax * by - ay * bx;
			tiltRow(rows, id, t1x, t1y, t1z, ex * t1x + ey * t1y + ez * t1z, h, tiltImpulse1);
			tiltRow(rows, id, t2x, t2y, t2z, ex * t2x + ey * t2y + ez * t2z, h, tiltImpulse2);
		} else {
			tiltImpulse1[id] = tiltImpulse2[id] = 0.0;
		}
		var rax = refAX[id], ray = refAY[id], raz = refAZ[id];
		var rbx = refBX[id], rby = refBY[id], rbz = refBZ[id];
		var sine = ax * (ray * rbz - raz * rby) + ay * (raz * rbx - rax * rbz) + az * (rax * rby - ray * rbx);
		var cosine = rax * rbx + ray * rby + raz * rbz;
		var angle = Math.atan2(sine, cosine);
		var state = angle < lowerAngle[id] ? 1 : (angle > upperAngle[id] ? -1 : 0);
		if (state != limitState[id])
			limitImpulse[id] = 0.0;
		limitState[id] = state;
		var speed:Float, damping:Float, maxImpulse:Float;
		if (driveConfigured[id] != 0) {
			var target = Math.max(lowerAngle[id], Math.min(upperAngle[id], driveTarget[id]));
			speed = driveStiffness[id] * (target - angle);
			damping = driveDamping[id];
			maxImpulse = driveStiffness[id] > 0.0 ? driveTorque[id] * h : 0.0;
		} else {
			speed = motorSpeed[id];
			damping = 1.0;
			maxImpulse = maxMotorTorque[id] * h;
		}
		motorImpulse[id] = Math.max(-maxImpulse, Math.min(maxImpulse, motorImpulse[id]));
		// A motor pushing into an active limit is left to the limit row.
		var blocked = state == 1 && speed < 0.0 || state == -1 && speed > 0.0;
		if (blocked)
			motorImpulse[id] = 0.0;
		if (state != 0) {
			var k = rows.angular(ax, ay, az);
			var mass = k > 0.0 ? 1.0 / k : 0.0;
			var bias = positionBias(angle - (state == 1 ? lowerAngle[id] : upperAngle[id]), h);
			rows.set(-mass * bias, mass, 0.0, state == 1 ? 0.0 : Math.NEGATIVE_INFINITY, state == 1 ? Math.POSITIVE_INFINITY : 0.0, limitImpulse, id);
			rows.relaxWithout();
		}
		if (maxImpulse > 0.0 && !blocked) {
			var k = rows.angular(ax, ay, az);
			var mass = k > 0.0 ? 1.0 / k : 0.0;
			// Solved exactly toward speed / damping; with no damping the push is limited by the torque alone.
			if (damping > 0.0)
				rows.set(mass * speed / damping, mass, 0.0, -maxImpulse, maxImpulse, motorImpulse, id);
			else
				rows.set(mass * speed, 0.0, 0.0, -maxImpulse, maxImpulse, motorImpulse, id);
		}
	}

	/** The hinge angle the solver would measure with its bodies at rotations `qa` and `qb`. */
	public function angleFor(id:Int, qa:Quat, qb:Quat):Float {
		var ax = localAxisAX[id], ay = localAxisAY[id], az = localAxisAZ[id];
		var rax = localRefAX[id], ray = localRefAY[id], raz = localRefAZ[id];
		var rbx = localRefBX[id], rby = localRefBY[id], rbz = localRefBZ[id];
		// Axis and reference vectors into world space: v + w t + q x t, with t = 2 q x v.
		var tx = 2.0 * (qa.y * az - qa.z * ay),
			ty = 2.0 * (qa.z * ax - qa.x * az),
			tz = 2.0 * (qa.x * ay - qa.y * ax);
		var wax = ax + qa.w * tx + qa.y * tz - qa.z * ty,
			way = ay + qa.w * ty + qa.z * tx - qa.x * tz,
			waz = az + qa.w * tz + qa.x * ty - qa.y * tx;
		tx = 2.0 * (qa.y * raz - qa.z * ray);
		ty = 2.0 * (qa.z * rax - qa.x * raz);
		tz = 2.0 * (qa.x * ray - qa.y * rax);
		var wrax = rax + qa.w * tx + qa.y * tz - qa.z * ty,
			wray = ray + qa.w * ty + qa.z * tx - qa.x * tz;
		var wraz = raz + qa.w * tz + qa.x * ty - qa.y * tx;
		tx = 2.0 * (qb.y * rbz - qb.z * rby);
		ty = 2.0 * (qb.z * rbx - qb.x * rbz);
		tz = 2.0 * (qb.x * rby - qb.y * rbx);
		var wrbx = rbx + qb.w * tx + qb.y * tz - qb.z * ty,
			wrby = rby + qb.w * ty + qb.z * tx - qb.x * tz;
		var wrbz = rbz + qb.w * tz + qb.x * ty - qb.y * tx;
		var sine = wax * (wray * wrbz - wraz * wrby) + way * (wraz * wrbx - wrax * wrbz) + waz * (wrax * wrby - wray * wrbx);
		return Math.atan2(sine, wrax * wrbx + wray * wrby + wraz * wrbz);
	}

	function rotateInto(body:Int, lx:Float, ly:Float, lz:Float, outX:FloatBuffer, outY:FloatBuffer, outZ:FloatBuffer, id:Int):Void {
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

	/** Visits settings and warm starts for `WorldSnapshot`; the world-space axes are rebuilt every substep. */
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
		s.floats(pointImpulseX, joints);
		s.floats(pointImpulseY, joints);
		s.floats(pointImpulseZ, joints);
		s.floats(tiltImpulse1, joints);
		s.floats(tiltImpulse2, joints);
		s.floats(limitImpulse, joints);
		s.floats(motorImpulse, joints);
		s.floats(lowerAngle, joints);
		s.floats(upperAngle, joints);
		s.floats(motorSpeed, joints);
		s.floats(maxMotorTorque, joints);
		s.floats(driveTarget, joints);
		s.floats(driveStiffness, joints);
		s.floats(driveDamping, joints);
		s.floats(driveTorque, joints);
		s.ints(limitState, joints);
		s.ints(driveConfigured, joints);
	}
}
