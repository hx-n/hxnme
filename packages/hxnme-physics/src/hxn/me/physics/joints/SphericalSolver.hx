package hxn.me.physics.joints;

import hxn.me.math.Grow;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.Float32Buffer;
import hxn.Int32Buffer;

class SphericalSolver {
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
	var pointImpulseX:Float32Buffer;
	var pointImpulseY:Float32Buffer;
	var pointImpulseZ:Float32Buffer;
	var swingImpulse:Float32Buffer;
	var swingActive:Int32Buffer;
	var twistImpulse:Float32Buffer;
	var twistState:Int32Buffer;
	var swingLimit:Float32Buffer;
	var lowerTwist:Float32Buffer;
	var upperTwist:Float32Buffer;
	var neutralX:Float32Buffer;
	var neutralY:Float32Buffer;
	var neutralZ:Float32Buffer;
	var neutralW:Float32Buffer;
	var targetX:Float32Buffer;
	var targetY:Float32Buffer;
	var targetZ:Float32Buffer;
	var targetW:Float32Buffer;
	var driveGain:Float32Buffer;
	var driveDamping:Float32Buffer;
	var driveTorque:Float32Buffer;
	var driveImpulseX:Float32Buffer;
	var driveImpulseY:Float32Buffer;
	var driveImpulseZ:Float32Buffer;
	// These buffers hold the axes along which the drive impulses above were last solved.
	var driveAxis0X:Float32Buffer;
	var driveAxis0Y:Float32Buffer;
	var driveAxis0Z:Float32Buffer;
	var driveAxis1X:Float32Buffer;
	var driveAxis1Y:Float32Buffer;
	var driveAxis1Z:Float32Buffer;
	var driveAxis2X:Float32Buffer;
	var driveAxis2Y:Float32Buffer;
	var driveAxis2Z:Float32Buffer;

	static inline function multiply(a:Quat, b:Quat):Quat {
		return new Quat(a.w * b.x
			+ a.x * b.w
			+ a.y * b.z
			- a.z * b.y, a.w * b.y
			- a.x * b.z
			+ a.y * b.w
			+ a.z * b.x,
			a.w * b.z
			+ a.x * b.y
			- a.y * b.x
			+ a.z * b.w, a.w * b.w
			- a.x * b.x
			- a.y * b.y
			- a.z * b.z);
	}

	static inline function conjugate(q:Quat):Quat
		return new Quat(-q.x, -q.y, -q.z, q.w);

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
		pointImpulseX = new Float32Buffer(capacity);
		pointImpulseY = new Float32Buffer(capacity);
		pointImpulseZ = new Float32Buffer(capacity);
		swingImpulse = new Float32Buffer(capacity);
		swingActive = new Int32Buffer(capacity);
		twistImpulse = new Float32Buffer(capacity);
		twistState = new Int32Buffer(capacity);
		swingLimit = new Float32Buffer(capacity);
		lowerTwist = new Float32Buffer(capacity);
		upperTwist = new Float32Buffer(capacity);
		neutralX = new Float32Buffer(capacity);
		neutralY = new Float32Buffer(capacity);
		neutralZ = new Float32Buffer(capacity);
		neutralW = new Float32Buffer(capacity);
		targetX = new Float32Buffer(capacity);
		targetY = new Float32Buffer(capacity);
		targetZ = new Float32Buffer(capacity);
		targetW = new Float32Buffer(capacity);
		driveGain = new Float32Buffer(capacity);
		driveDamping = new Float32Buffer(capacity);
		driveTorque = new Float32Buffer(capacity);
		driveImpulseX = new Float32Buffer(capacity);
		driveImpulseY = new Float32Buffer(capacity);
		driveImpulseZ = new Float32Buffer(capacity);
		driveAxis0X = new Float32Buffer(capacity);
		driveAxis0Y = new Float32Buffer(capacity);
		driveAxis0Z = new Float32Buffer(capacity);
		driveAxis1X = new Float32Buffer(capacity);
		driveAxis1Y = new Float32Buffer(capacity);
		driveAxis1Z = new Float32Buffer(capacity);
		driveAxis2X = new Float32Buffer(capacity);
		driveAxis2Y = new Float32Buffer(capacity);
		driveAxis2Z = new Float32Buffer(capacity);
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
		pointImpulseX = Grow.floats(pointImpulseX, from, to);
		pointImpulseY = Grow.floats(pointImpulseY, from, to);
		pointImpulseZ = Grow.floats(pointImpulseZ, from, to);
		swingImpulse = Grow.floats(swingImpulse, from, to);
		swingActive = Grow.ints(swingActive, from, to);
		twistImpulse = Grow.floats(twistImpulse, from, to);
		twistState = Grow.ints(twistState, from, to);
		swingLimit = Grow.floats(swingLimit, from, to);
		lowerTwist = Grow.floats(lowerTwist, from, to);
		upperTwist = Grow.floats(upperTwist, from, to);
		neutralX = Grow.floats(neutralX, from, to);
		neutralY = Grow.floats(neutralY, from, to);
		neutralZ = Grow.floats(neutralZ, from, to);
		neutralW = Grow.floats(neutralW, from, to);
		targetX = Grow.floats(targetX, from, to);
		targetY = Grow.floats(targetY, from, to);
		targetZ = Grow.floats(targetZ, from, to);
		targetW = Grow.floats(targetW, from, to);
		driveGain = Grow.floats(driveGain, from, to);
		driveDamping = Grow.floats(driveDamping, from, to);
		driveTorque = Grow.floats(driveTorque, from, to);
		driveImpulseX = Grow.floats(driveImpulseX, from, to);
		driveImpulseY = Grow.floats(driveImpulseY, from, to);
		driveImpulseZ = Grow.floats(driveImpulseZ, from, to);
		driveAxis0X = Grow.floats(driveAxis0X, from, to);
		driveAxis0Y = Grow.floats(driveAxis0Y, from, to);
		driveAxis0Z = Grow.floats(driveAxis0Z, from, to);
		driveAxis1X = Grow.floats(driveAxis1X, from, to);
		driveAxis1Y = Grow.floats(driveAxis1Y, from, to);
		driveAxis1Z = Grow.floats(driveAxis1Z, from, to);
		driveAxis2X = Grow.floats(driveAxis2X, from, to);
		driveAxis2Y = Grow.floats(driveAxis2Y, from, to);
		driveAxis2Z = Grow.floats(driveAxis2Z, from, to);
	}


	public function initialize(id:Int, qa:Quat, qb:Quat, axis:Vec3, swing:Single, lower:Single, upper:Single):Void {
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
		var neutral = multiply(conjugate(qa), qb);
		neutralX[id] = neutral.x;
		neutralY[id] = neutral.y;
		neutralZ[id] = neutral.z;
		neutralW[id] = neutral.w;
		targetX[id] = neutral.x;
		targetY[id] = neutral.y;
		targetZ[id] = neutral.z;
		targetW[id] = neutral.w;
		driveGain[id] = driveDamping[id] = driveTorque[id] = 0.0;
		driveImpulseX[id] = driveImpulseY[id] = driveImpulseZ[id] = 0.0;
		swingLimit[id] = swing;
		lowerTwist[id] = lower;
		upperTwist[id] = upper;
		pointImpulseX[id] = pointImpulseY[id] = pointImpulseZ[id] = 0.0;
		swingImpulse[id] = twistImpulse[id] = 0.0;
		swingActive[id] = twistState[id] = 0;
	}

	/**
	 * Reflects the joint's frames through the plane that the diagonal
	 * reflection (ex, ey, ez) fixes, in each body's frame, as
	 * `HingeSolver.mirror` does. The neutral and target relative rotations
	 * reflect with them, so swing and twist keep their limits as the relative
	 * turn of the bodies mirrors.
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
		// Reflected by E, a rotation is the quaternion (-E v, w).
		neutralX[id] *= -ex;
		neutralY[id] *= -ey;
		neutralZ[id] *= -ez;
		targetX[id] *= -ex;
		targetY[id] *= -ey;
		targetZ[id] *= -ez;
		driveImpulseX[id] = driveImpulseY[id] = driveImpulseZ[id] = 0.0;
		pointImpulseX[id] = pointImpulseY[id] = pointImpulseZ[id] = 0.0;
		swingImpulse[id] = twistImpulse[id] = 0.0;
		swingActive[id] = twistState[id] = 0;
	}

	/** Writes to `out` the drive offset that holds the bodies at rotations `qa` and `qb`: (qa⁻¹·qb)·neutral⁻¹. */
	public function offsetFor(id:Int, qa:Quat, qb:Quat, out:Quat):Quat {
		var rx = qa.w * qb.x - qa.x * qb.w - qa.y * qb.z + qa.z * qb.y;
		var ry = qa.w * qb.y + qa.x * qb.z - qa.y * qb.w - qa.z * qb.x;
		var rz = qa.w * qb.z - qa.x * qb.y + qa.y * qb.x - qa.z * qb.w;
		var rw = qa.w * qb.w + qa.x * qb.x + qa.y * qb.y + qa.z * qb.z;
		var nx:Float = -neutralX[id],
			ny:Float = -neutralY[id],
			nz:Float = -neutralZ[id],
			nw:Float = neutralW[id];
		out.x = rw * nx + rx * nw + ry * nz - rz * ny;
		out.y = rw * ny - rx * nz + ry * nw + rz * nx;
		out.z = rw * nz + rx * ny - ry * nx + rz * nw;
		out.w = rw * nw - rx * nx - ry * ny - rz * nz;
		return out;
	}

	public function setDrive(id:Int, offset:Quat, stiffness:Single, damping:Single, maxTorque:Single):Void {
		var length = Math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z + offset.w * offset.w);
		var sign = offset.w < 0.0 ? -1.0 / length : 1.0 / length;
		var qx = offset.x * sign,
			qy = offset.y * sign,
			qz = offset.z * sign,
			qw = offset.w * sign;
		var ax = localAxisAX[id], ay = localAxisAY[id], az = localAxisAZ[id];
		var projection = qx * ax + qy * ay + qz * az;
		var twistLength = Math.sqrt(projection * projection + qw * qw);
		var tx = 0.0, ty = 0.0, tz = 0.0, tw = 1.0;
		if (twistLength > 1e-6) {
			var projected = projection / twistLength;
			tx = ax * projected;
			ty = ay * projected;
			tz = az * projected;
			tw = qw / twistLength;
		}
		var sx = -qw * tx + qx * tw - qy * tz + qz * ty;
		var sy = -qw * ty + qx * tz + qy * tw - qz * tx;
		var sz = -qw * tz - qx * ty + qy * tx + qz * tw;
		var sw = qw * tw + qx * tx + qy * ty + qz * tz;
		var swingLength = Math.sqrt(sx * sx + sy * sy + sz * sz);
		var swingAngle = 2.0 * Math.atan2(swingLength, Math.abs(sw));
		if (swingLength > 1e-6 && swingAngle > swingLimit[id]) {
			var s = Math.sin(swingLimit[id] * 0.5) / swingLength;
			sx *= s;
			sy *= s;
			sz *= s;
			sw = Math.cos(swingLimit[id] * 0.5);
		}
		var twistAngle = 2.0 * Math.atan2(projection, qw);
		if (twistAngle > Math.PI)
			twistAngle -= 2.0 * Math.PI;
		if (twistAngle < -Math.PI)
			twistAngle += 2.0 * Math.PI;
		twistAngle = Math.max(lowerTwist[id], Math.min(upperTwist[id], twistAngle));
		var half = twistAngle * 0.5;
		var sine = Math.sin(half), cosine = Math.cos(half);
		tx = ax * sine;
		ty = ay * sine;
		tz = az * sine;
		tw = cosine;
		var cx = sw * tx + sx * tw + sy * tz - sz * ty;
		var cy = sw * ty - sx * tz + sy * tw + sz * tx;
		var cz = sw * tz + sx * ty - sy * tx + sz * tw;
		var cw = sw * tw - sx * tx - sy * ty - sz * tz;
		var nx = neutralX[id],
			ny = neutralY[id],
			nz = neutralZ[id],
			nw = neutralW[id];
		var rx = cw * nx + cx * nw + cy * nz - cz * ny;
		var ry = cw * ny - cx * nz + cy * nw + cz * nx;
		var rz = cw * nz + cx * ny - cy * nx + cz * nw;
		var rw = cw * nw - cx * nx - cy * ny - cz * nz;
		var alignment = Math.abs(rx * targetX[id] + ry * targetY[id] + rz * targetZ[id] + rw * targetW[id]);
		if (driveGain[id] == 0.0 || alignment < 0.95) {
			driveImpulseX[id] = driveImpulseY[id] = driveImpulseZ[id] = 0.0;
		}
		targetX[id] = rx;
		targetY[id] = ry;
		targetZ[id] = rz;
		targetW[id] = rw;
		driveGain[id] = stiffness;
		driveDamping[id] = damping;
		driveTorque[id] = maxTorque;
	}

	inline function positionBias(error:Float, h:Single):Single {
		var correction = Math.max(0.0, Math.abs(error) - 0.001);
		return Math.max(-10.0, Math.min(10.0, 0.2 * (error < 0.0 ? -correction : correction) / h));
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

	inline function pointRow(rows:JointRows, id:Int, x:Float, y:Float, z:Float, error:Float, h:Single, store:Float32Buffer):Void {
		var k = rows.linear(x, y, z, pool.rAX[id], pool.rAY[id], pool.rAZ[id], pool.rBX[id], pool.rBY[id], pool.rBZ[id]);
		rows.setEquality(k > 0.0 ? 1.0 / k : 0.0, positionBias(error, h), 0.0, store, id);
	}

	/** Emits point rows, the optional drive block, and active swing and twist limit rows. */
	public function prepare(id:Int, dx:Float, dy:Float, dz:Float, h:Single):Void {
		var world = pool.world, rows = pool.rows;
		var a = pool.bodyA[id], b = pool.bodyB[id];
		pointRow(rows, id, 1, 0, 0, dx, h, pointImpulseX);
		pointRow(rows, id, 0, 1, 0, dy, h, pointImpulseY);
		pointRow(rows, id, 0, 0, 1, dz, h, pointImpulseZ);
		var limit = driveGain[id] > 0.0 ? driveTorque[id] * h : 0.0;
		if (limit > 0.0) {
			var previous = Math.sqrt(driveImpulseX[id] * driveImpulseX[id] + driveImpulseY[id] * driveImpulseY[id] + driveImpulseZ[id] * driveImpulseZ[id]);
			if (previous > limit) {
				var reduced = limit / previous;
				driveImpulseX[id] *= reduced;
				driveImpulseY[id] *= reduced;
				driveImpulseZ[id] *= reduced;
			}
			var qax = world.rotX[a],
				qay = world.rotY[a],
				qaz = world.rotZ[a],
				qaw = world.rotW[a];
			var tx = targetX[id],
				ty = targetY[id],
				tz = targetZ[id],
				tw = targetW[id];
			var dxq = qaw * tx + qax * tw + qay * tz - qaz * ty;
			var dyq = qaw * ty - qax * tz + qay * tw + qaz * tx;
			var dzq = qaw * tz + qax * ty - qay * tx + qaz * tw;
			var dwq = qaw * tw - qax * tx - qay * ty - qaz * tz;
			var bxq = world.rotX[b],
				byq = world.rotY[b],
				bzq = world.rotZ[b],
				bwq = world.rotW[b];
			var ex = -dwq * bxq + dxq * bwq - dyq * bzq + dzq * byq;
			var ey = -dwq * byq + dxq * bzq + dyq * bwq - dzq * bxq;
			var ez = -dwq * bzq - dxq * byq + dyq * bxq + dzq * bwq;
			var ew = dwq * bwq + dxq * bxq + dyq * byq + dzq * bzq;
			var sign = ew < 0.0 ? -1.0 : 1.0;
			var magnitude = Math.sqrt(ex * ex + ey * ey + ez * ez);
			var scale = magnitude < 1e-6 ? 2.0 * sign : 2.0 * Math.atan2(magnitude, Math.abs(ew)) * sign / magnitude;
			var gain = driveGain[id], damping = driveDamping[id];
			var wx = gain * ex * scale,
				wy = gain * ey * scale,
				wz = gain * ez * scale;
			// Converts the impulse of the last step to a world vector, so it can warm start along the axes
			// of this step.
			var ix:Float = driveImpulseX[id],
				iy:Float = driveImpulseY[id],
				iz:Float = driveImpulseZ[id];
			var lx = ix * driveAxis0X[id] + iy * driveAxis1X[id] + iz * driveAxis2X[id];
			var ly = ix * driveAxis0Y[id] + iy * driveAxis1Y[id] + iz * driveAxis2Y[id];
			var lz = ix * driveAxis0Z[id] + iy * driveAxis1Z[id] + iz * driveAxis2Z[id];
			principalAxes(id, world.invIxx[a]
				+ world.invIxx[b], world.invIyy[a]
				+ world.invIyy[b], world.invIzz[a]
				+ world.invIzz[b],
				world.invIxy[a]
				+ world.invIxy[b], world.invIxz[a]
				+ world.invIxz[b], world.invIyz[a]
				+ world.invIyz[b]);
			var x0:Float = driveAxis0X[id],
				y0:Float = driveAxis0Y[id],
				z0:Float = driveAxis0Z[id];
			var x1:Float = driveAxis1X[id],
				y1:Float = driveAxis1Y[id],
				z1:Float = driveAxis1Z[id];
			var x2:Float = driveAxis2X[id],
				y2:Float = driveAxis2Y[id],
				z2:Float = driveAxis2Z[id];
			driveImpulseX[id] = lx * x0 + ly * y0 + lz * z0;
			driveImpulseY[id] = lx * x1 + ly * y1 + lz * z1;
			driveImpulseZ[id] = lx * x2 + ly * y2 + lz * z2;
			driveRow(rows, id, x0, y0, z0, wx * x0 + wy * y0 + wz * z0, damping, driveImpulseX);
			driveRow(rows, id, x1, y1, z1, wx * x1 + wy * y1 + wz * z1, damping, driveImpulseY);
			driveRow(rows, id, x2, y2, z2, wx * x2 + wy * y2 + wz * z2, damping, driveImpulseZ);
			rows.normBlock(limit);
		} else {
			driveImpulseX[id] = driveImpulseY[id] = driveImpulseZ[id] = 0.0;
		}
		rotateInto(a, localAxisAX[id], localAxisAY[id], localAxisAZ[id], axisAX, axisAY, axisAZ, id);
		rotateInto(b, localAxisBX[id], localAxisBY[id], localAxisBZ[id], axisBX, axisBY, axisBZ, id);
		rotateInto(a, localRefAX[id], localRefAY[id], localRefAZ[id], refAX, refAY, refAZ, id);
		rotateInto(b, localRefBX[id], localRefBY[id], localRefBZ[id], refBX, refBY, refBZ, id);
		var ax = axisAX[id], ay = axisAY[id], az = axisAZ[id];
		var bx = axisBX[id], by = axisBY[id], bz = axisBZ[id];
		var cx = ay * bz - az * by,
			cy = az * bx - ax * bz,
			cz = ax * by - ay * bx;
		var crossLength = Math.sqrt(cx * cx + cy * cy + cz * cz);
		var angle = Math.atan2(crossLength, Math.max(-1.0, Math.min(1.0, ax * bx + ay * by + az * bz)));
		var active = angle > swingLimit[id] ? 1 : 0;
		if (active != swingActive[id])
			swingImpulse[id] = 0.0;
		swingActive[id] = active;
		if (active != 0) {
			var inv = crossLength > 1e-6 ? 1.0 / crossLength : 0.0;
			var sx = crossLength > 1e-6 ? cx * inv : refAX[id];
			var sy = crossLength > 1e-6 ? cy * inv : refAY[id];
			var sz = crossLength > 1e-6 ? cz * inv : refAZ[id];
			var k = rows.angular(sx, sy, sz);
			var mass = k > 0.0 ? 1.0 / k : 0.0;
			rows.set(-mass * positionBias(angle - swingLimit[id], h), mass, 0.0, Math.NEGATIVE_INFINITY, 0.0, swingImpulse, id);
			rows.relaxWithout();
		} else {
			swingImpulse[id] = 0.0;
		}
		var dot = ax * bx + ay * by + az * bz;
		var twist = 0.0;
		if (dot > -0.9999) {
			// Shortest-arc alignment removes swing before measuring twist.
			var qx = (by * az - bz * ay),
				qy = (bz * ax - bx * az),
				qz = (bx * ay - by * ax);
			var invLength = 1.0 / Math.sqrt(2.0 * (1.0 + dot));
			qx *= invLength;
			qy *= invLength;
			qz *= invLength;
			var qw = (1.0 + dot) * invLength;
			var rx = refBX[id], ry = refBY[id], rz = refBZ[id];
			var tx = 2.0 * (qy * rz - qz * ry),
				ty = 2.0 * (qz * rx - qx * rz),
				tz = 2.0 * (qx * ry - qy * rx);
			var alignedX = rx + qw * tx + qy * tz - qz * ty;
			var alignedY = ry + qw * ty + qz * tx - qx * tz;
			var alignedZ = rz + qw * tz + qx * ty - qy * tx;
			var ux = refAX[id], uy = refAY[id], uz = refAZ[id];
			var sine = ax * (uy * alignedZ - uz * alignedY) + ay * (uz * alignedX - ux * alignedZ) + az * (ux * alignedY - uy * alignedX);
			twist = Math.atan2(sine, ux * alignedX + uy * alignedY + uz * alignedZ);
		}
		var state = twist < lowerTwist[id] ? 1 : (twist > upperTwist[id] ? -1 : 0);
		if (state != twistState[id])
			twistImpulse[id] = 0.0;
		twistState[id] = state;
		if (state != 0) {
			var k = rows.angular(ax, ay, az);
			var mass = k > 0.0 ? 1.0 / k : 0.0;
			var bias = positionBias(twist - (state == 1 ? lowerTwist[id] : upperTwist[id]), h);
			rows.set(-mass * bias, mass, 0.0, state == 1 ? 0.0 : Math.NEGATIVE_INFINITY, state == 1 ? Math.POSITIVE_INFINITY : 0.0, twistImpulse, id);
			rows.relaxWithout();
		} else {
			twistImpulse[id] = 0.0;
		}
	}

	/**
	 * Writes the eigenvectors of the joint's combined world inverse inertia to
	 * the drive axes, by cyclic Jacobi. Along these axes the three drive rows do not
	 * disturb one another, so the sequential solve converges for long, thin
	 * bodies whose inertia differs greatly between axes.
	 */
	function principalAxes(id:Int, a00:Float, a11:Float, a22:Float, a01:Float, a02:Float, a12:Float):Void {
		var v00 = 1.0, v01 = 0.0, v02 = 0.0, v10 = 0.0, v11 = 1.0, v12 = 0.0, v20 = 0.0, v21 = 0.0, v22 = 1.0;
		var scale = Math.abs(a00) + Math.abs(a11) + Math.abs(a22);
		var sweep = 0;
		while (sweep < 6 && Math.abs(a01) + Math.abs(a02) + Math.abs(a12) > 1e-9 * scale) {
			sweep++;
			if (a01 != 0.0) {
				var theta = (a11 - a00) / (2.0 * a01);
				var t = (theta < 0.0 ? -1.0 : 1.0) / (Math.abs(theta) + Math.sqrt(theta * theta + 1.0));
				var c = 1.0 / Math.sqrt(t * t + 1.0), s = t * c;
				a00 -= t * a01;
				a11 += t * a01;
				a01 = 0.0;
				var p = c * a02 - s * a12, q = s * a02 + c * a12;
				a02 = p;
				a12 = q;
				p = c * v00 - s * v01;
				q = s * v00 + c * v01;
				v00 = p;
				v01 = q;
				p = c * v10 - s * v11;
				q = s * v10 + c * v11;
				v10 = p;
				v11 = q;
				p = c * v20 - s * v21;
				q = s * v20 + c * v21;
				v20 = p;
				v21 = q;
			}
			if (a02 != 0.0) {
				var theta = (a22 - a00) / (2.0 * a02);
				var t = (theta < 0.0 ? -1.0 : 1.0) / (Math.abs(theta) + Math.sqrt(theta * theta + 1.0));
				var c = 1.0 / Math.sqrt(t * t + 1.0), s = t * c;
				a00 -= t * a02;
				a22 += t * a02;
				a02 = 0.0;
				var p = c * a01 - s * a12, q = s * a01 + c * a12;
				a01 = p;
				a12 = q;
				p = c * v00 - s * v02;
				q = s * v00 + c * v02;
				v00 = p;
				v02 = q;
				p = c * v10 - s * v12;
				q = s * v10 + c * v12;
				v10 = p;
				v12 = q;
				p = c * v20 - s * v22;
				q = s * v20 + c * v22;
				v20 = p;
				v22 = q;
			}
			if (a12 != 0.0) {
				var theta = (a22 - a11) / (2.0 * a12);
				var t = (theta < 0.0 ? -1.0 : 1.0) / (Math.abs(theta) + Math.sqrt(theta * theta + 1.0));
				var c = 1.0 / Math.sqrt(t * t + 1.0), s = t * c;
				a11 -= t * a12;
				a22 += t * a12;
				a12 = 0.0;
				var p = c * a01 - s * a02, q = s * a01 + c * a02;
				a01 = p;
				a02 = q;
				p = c * v01 - s * v02;
				q = s * v01 + c * v02;
				v01 = p;
				v02 = q;
				p = c * v11 - s * v12;
				q = s * v11 + c * v12;
				v11 = p;
				v12 = q;
				p = c * v21 - s * v22;
				q = s * v21 + c * v22;
				v21 = p;
				v22 = q;
			}
		}
		driveAxis0X[id] = v00;
		driveAxis0Y[id] = v10;
		driveAxis0Z[id] = v20;
		driveAxis1X[id] = v01;
		driveAxis1Y[id] = v11;
		driveAxis1Z[id] = v21;
		driveAxis2X[id] = v02;
		driveAxis2Y[id] = v12;
		driveAxis2Z[id] = v22;
	}

	inline function driveRow(rows:JointRows, id:Int, x:Float, y:Float, z:Float, gainError:Float, damping:Float, store:Float32Buffer):Void {
		var k = rows.angular(x, y, z);
		var mass = k > 0.0 ? 1.0 / k : 0.0;
		// Solves exactly toward speed stiffness * error / damping. With no damping, only the torque
		// limits the push.
		if (damping > 0.0)
			rows.set(mass * gainError / damping, mass, 0.0, Math.NEGATIVE_INFINITY, Math.POSITIVE_INFINITY, store, id);
		else
			rows.set(mass * gainError, 0.0, 0.0, Math.NEGATIVE_INFINITY, Math.POSITIVE_INFINITY, store, id);
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
		s.floats(pointImpulseX, joints);
		s.floats(pointImpulseY, joints);
		s.floats(pointImpulseZ, joints);
		s.floats(swingImpulse, joints);
		s.floats(twistImpulse, joints);
		s.floats(swingLimit, joints);
		s.floats(lowerTwist, joints);
		s.floats(upperTwist, joints);
		s.floats(neutralX, joints);
		s.floats(neutralY, joints);
		s.floats(neutralZ, joints);
		s.floats(neutralW, joints);
		s.floats(targetX, joints);
		s.floats(targetY, joints);
		s.floats(targetZ, joints);
		s.floats(targetW, joints);
		s.floats(driveGain, joints);
		s.floats(driveDamping, joints);
		s.floats(driveTorque, joints);
		s.floats(driveImpulseX, joints);
		s.floats(driveImpulseY, joints);
		s.floats(driveImpulseZ, joints);
		s.floats(driveAxis0X, joints);
		s.floats(driveAxis0Y, joints);
		s.floats(driveAxis0Z, joints);
		s.floats(driveAxis1X, joints);
		s.floats(driveAxis1Y, joints);
		s.floats(driveAxis1Z, joints);
		s.floats(driveAxis2X, joints);
		s.floats(driveAxis2Y, joints);
		s.floats(driveAxis2Z, joints);
		s.ints(swingActive, joints);
		s.ints(twistState, joints);
	}
}
