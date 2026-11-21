package hxn.me.physics.joints;

import hxn.me.math.Grow;
import hxn.me.math.Quat;
import hxn.me.math.Simd.FloatBuffer;
import hxn.me.physics.core.Handles.DoFMask;

class WeldSolver {
	var pool:JointPool;
	var relativeX:FloatBuffer;
	var relativeY:FloatBuffer;
	var relativeZ:FloatBuffer;
	var relativeW:FloatBuffer;
	var frequencyHz:FloatBuffer;
	var dampingRatio:FloatBuffer;
	var linearImpulseX:FloatBuffer;
	var linearImpulseY:FloatBuffer;
	var linearImpulseZ:FloatBuffer;
	var angularImpulseX:FloatBuffer;
	var angularImpulseY:FloatBuffer;
	var angularImpulseZ:FloatBuffer;

	public function new(pool:JointPool, capacity:Int) {
		this.pool = pool;
		relativeX = new FloatBuffer(capacity);
		relativeY = new FloatBuffer(capacity);
		relativeZ = new FloatBuffer(capacity);
		relativeW = new FloatBuffer(capacity);
		frequencyHz = new FloatBuffer(capacity);
		dampingRatio = new FloatBuffer(capacity);
		linearImpulseX = new FloatBuffer(capacity);
		linearImpulseY = new FloatBuffer(capacity);
		linearImpulseZ = new FloatBuffer(capacity);
		angularImpulseX = new FloatBuffer(capacity);
		angularImpulseY = new FloatBuffer(capacity);
		angularImpulseZ = new FloatBuffer(capacity);
	}

	/** Room for `to` joints, keeping the first `from`. */
	public function grow(from:Int, to:Int):Void {
		relativeX = Grow.floats(relativeX, from, to);
		relativeY = Grow.floats(relativeY, from, to);
		relativeZ = Grow.floats(relativeZ, from, to);
		relativeW = Grow.floats(relativeW, from, to);
		frequencyHz = Grow.floats(frequencyHz, from, to);
		dampingRatio = Grow.floats(dampingRatio, from, to);
		linearImpulseX = Grow.floats(linearImpulseX, from, to);
		linearImpulseY = Grow.floats(linearImpulseY, from, to);
		linearImpulseZ = Grow.floats(linearImpulseZ, from, to);
		angularImpulseX = Grow.floats(angularImpulseX, from, to);
		angularImpulseY = Grow.floats(angularImpulseY, from, to);
		angularImpulseZ = Grow.floats(angularImpulseZ, from, to);
	}


	public function initialize(id:Int, qa:Quat, qb:Quat, frequency:Single, damping:Single):Void {
		relativeX[id] = qa.w * qb.x - qa.x * qb.w - qa.y * qb.z + qa.z * qb.y;
		relativeY[id] = qa.w * qb.y + qa.x * qb.z - qa.y * qb.w - qa.z * qb.x;
		relativeZ[id] = qa.w * qb.z - qa.x * qb.y + qa.y * qb.x - qa.z * qb.w;
		relativeW[id] = qa.w * qb.w + qa.x * qb.x + qa.y * qb.y + qa.z * qb.z;
		frequencyHz[id] = frequency;
		dampingRatio[id] = damping;
		linearImpulseX[id] = linearImpulseY[id] = linearImpulseZ[id] = 0.0;
		angularImpulseX[id] = angularImpulseY[id] = angularImpulseZ[id] = 0.0;
	}

	/** Finishes a row with inverse effective mass `k`, soft when the weld has a frequency. */
	function finishRow(rows:JointRows, id:Int, k:Float, error:Float, h:Single, store:FloatBuffer):Void {
		if (k <= 0.0) {
			rows.setEquality(0.0, 0.0, 0.0, store, id);
			return;
		}
		var hz = frequencyHz[id];
		var gamma = 0.0, bias = 0.0;
		if (hz > 0.0) {
			var omega = 2.0 * Math.PI * hz;
			var stiffness = omega * omega / k;
			var damping = 2.0 * dampingRatio[id] * omega / k;
			var soft = h * (damping + h * stiffness);
			gamma = soft > 0.0 ? 1.0 / soft : 0.0;
			bias = error * h * stiffness * gamma;
		} else {
			var correction = Math.max(0.0, Math.abs(error) - 0.001);
			bias = Math.max(-10.0, Math.min(10.0, 0.2 * (error < 0.0 ? -correction : correction) / h));
		}
		rows.setEquality(1.0 / (k + gamma), bias, gamma, store, id);
	}

	inline function linearRow(rows:JointRows, id:Int, x:Float, y:Float, z:Float, error:Float, h:Single, store:FloatBuffer):Void {
		var k = rows.linear(x, y, z, pool.rAX[id], pool.rAY[id], pool.rAZ[id], pool.rBX[id], pool.rBY[id], pool.rBZ[id]);
		finishRow(rows, id, k, error, h, store);
	}

	/** Emits anchor rows and the angular rows that hold the relative orientation from creation. */
	public function prepare(id:Int, dx:Float, dy:Float, dz:Float, h:Single):Void {
		var world = pool.world, rows = pool.rows;
		var a = pool.bodyA[id], b = pool.bodyB[id];
		var spatial = world.bodyDoF[a] == DoFMask.Full3D || world.bodyDoF[b] == DoFMask.Full3D;
		linearRow(rows, id, 1, 0, 0, dx, h, linearImpulseX);
		linearRow(rows, id, 0, 1, 0, dy, h, linearImpulseY);
		if (spatial)
			linearRow(rows, id, 0, 0, 1, dz, h, linearImpulseZ);
		else
			linearImpulseZ[id] = 0.0;

		var ax = world.rotX[a],
			ay = world.rotY[a],
			az = world.rotZ[a],
			aw = world.rotW[a];
		var bx = world.rotX[b],
			by = world.rotY[b],
			bz = world.rotZ[b],
			bw = world.rotW[b];
		var rx = aw * bx - ax * bw - ay * bz + az * by;
		var ry = aw * by + ax * bz - ay * bw - az * bx;
		var rz = aw * bz - ax * by + ay * bx - az * bw;
		var rw = aw * bw + ax * bx + ay * by + az * bz;
		var ix = relativeX[id],
			iy = relativeY[id],
			iz = relativeZ[id],
			iw = relativeW[id];
		var ex = -rw * ix + rx * iw - ry * iz + rz * iy;
		var ey = -rw * iy + rx * iz + ry * iw - rz * ix;
		var ez = -rw * iz - rx * iy + ry * ix + rz * iw;
		var ew = rw * iw + rx * ix + ry * iy + rz * iz;
		var scale = ew < 0.0 ? -2.0 : 2.0;
		ex *= scale;
		ey *= scale;
		ez *= scale;
		var tx = 2.0 * (ay * ez - az * ey),
			ty = 2.0 * (az * ex - ax * ez),
			tz = 2.0 * (ax * ey - ay * ex);
		var wx = ex + aw * tx + ay * tz - az * ty;
		var wy = ey + aw * ty + az * tx - ax * tz;
		var wz = ez + aw * tz + ax * ty - ay * tx;
		if (spatial) {
			rows.angular(1, 0, 0);
			finishRow(rows, id, world.invIxx[a] + world.invIxx[b], wx, h, angularImpulseX);
			rows.angular(0, 1, 0);
			finishRow(rows, id, world.invIyy[a] + world.invIyy[b], wy, h, angularImpulseY);
		} else {
			angularImpulseX[id] = angularImpulseY[id] = 0.0;
		}
		rows.angular(0, 0, 1);
		finishRow(rows, id, world.invIzz[a] + world.invIzz[b], wz, h, angularImpulseZ);
	}

	/** Visits settings and warm starts for `WorldSnapshot`. */
	@:noCompletion public function visitState(s:hxn.me.physics.core.WorldSnapshot, joints:Int):Void {
		s.floats(relativeX, joints);
		s.floats(relativeY, joints);
		s.floats(relativeZ, joints);
		s.floats(relativeW, joints);
		s.floats(frequencyHz, joints);
		s.floats(dampingRatio, joints);
		s.floats(linearImpulseX, joints);
		s.floats(linearImpulseY, joints);
		s.floats(linearImpulseZ, joints);
		s.floats(angularImpulseX, joints);
		s.floats(angularImpulseY, joints);
		s.floats(angularImpulseZ, joints);
	}
}
