package hxn.me.physics.joints;

import ash.simd.Float32x4;
import hxn.me.math.Float32Bytes;

/**
 * Solves a batch of four joints of one color. The joints share no dynamic
 * body, so their velocities are gathered once, every row level is solved for
 * all four lanes, and each dynamic body is written back once.
 *
 * Only Float32x4's Haxe-inline operations (load, store, add, mul, gt, select)
 * appear here, so Ash can keep the temporaries in registers.
 */
class JointSimd4 {
	static inline var VEL_A = 0;
	static inline var ANG_A = 48;
	static inline var VEL_B = 96;
	static inline var ANG_B = 144;
	static inline var MINUS_ONE = 192;

	var scratch:Float32Bytes;

	public function new() {
		scratch = new Float32Bytes(208);
		scratch.clear(0, 208);
		for (lane in 0...4)
			scratch.setF32(MINUS_ONE + (lane << 2), -1.0);
	}

	static inline function field(packed:Float32Bytes, base:Int, field:Int):Float32x4 {
		return Float32x4.load(packed, base + (field << 4));
	}

	public function solve(rows:JointRows, batch:Int):Void {
		var world = rows.world;
		var joints = rows.batchJoint;
		var bodyA = rows.rowBodyA, bodyB = rows.rowBodyB;
		for (lane in 0...4) {
			var id = joints[batch * 4 + lane], o = lane << 2;
			if (id < 0) {
				// An empty lane: zero velocities and zero rows, so it changes nothing and is never written back.
				scratch.setF32(VEL_A + o, 0.0);
				scratch.setF32(VEL_A + 16 + o, 0.0);
				scratch.setF32(VEL_A + 32 + o, 0.0);
				scratch.setF32(ANG_A + o, 0.0);
				scratch.setF32(ANG_A + 16 + o, 0.0);
				scratch.setF32(ANG_A + 32 + o, 0.0);
				scratch.setF32(VEL_B + o, 0.0);
				scratch.setF32(VEL_B + 16 + o, 0.0);
				scratch.setF32(VEL_B + 32 + o, 0.0);
				scratch.setF32(ANG_B + o, 0.0);
				scratch.setF32(ANG_B + 16 + o, 0.0);
				scratch.setF32(ANG_B + 32 + o, 0.0);
				continue;
			}
			var r = rows.jointStart[id];
			var a = bodyA[r], b = bodyB[r];
			scratch.setF32(VEL_A + o, world.velX[a]);
			scratch.setF32(VEL_A + 16 + o, world.velY[a]);
			scratch.setF32(VEL_A + 32 + o, world.velZ[a]);
			scratch.setF32(ANG_A + o, world.angVelX[a]);
			scratch.setF32(ANG_A + 16 + o, world.angVelY[a]);
			scratch.setF32(ANG_A + 32 + o, world.angVelZ[a]);
			scratch.setF32(VEL_B + o, world.velX[b]);
			scratch.setF32(VEL_B + 16 + o, world.velY[b]);
			scratch.setF32(VEL_B + 32 + o, world.velZ[b]);
			scratch.setF32(ANG_B + o, world.angVelX[b]);
			scratch.setF32(ANG_B + 16 + o, world.angVelY[b]);
			scratch.setF32(ANG_B + 32 + o, world.angVelZ[b]);
		}
		var vax = Float32x4.load(scratch, VEL_A),
			vay = Float32x4.load(scratch, VEL_A + 16),
			vaz = Float32x4.load(scratch, VEL_A + 32);
		var wax = Float32x4.load(scratch, ANG_A),
			way = Float32x4.load(scratch, ANG_A + 16),
			waz = Float32x4.load(scratch, ANG_A + 32);
		var vbx = Float32x4.load(scratch, VEL_B),
			vby = Float32x4.load(scratch, VEL_B + 16),
			vbz = Float32x4.load(scratch, VEL_B + 32);
		var wbx = Float32x4.load(scratch, ANG_B),
			wby = Float32x4.load(scratch, ANG_B + 16),
			wbz = Float32x4.load(scratch, ANG_B + 32);
		var minusOne = Float32x4.load(scratch, MINUS_ONE);

		var packed = rows.packed;
		var level = rows.batchLevelStart[batch];
		var end = level + rows.batchLevels[batch];
		while (level < end) {
			var base = level * JointRows.LEVEL_BYTES;
			var dx = field(packed, base, JointRows.DIR);
			var dy = field(packed, base, JointRows.DIR + 1);
			var dz = field(packed, base, JointRows.DIR + 2);
			var speed = (vbx + vax * minusOne) * dx + (vby + vay * minusOne) * dy + (vbz + vaz * minusOne) * dz
				+ wbx * field(packed, base, JointRows.JACOBIAN_B) + wby * field(packed, base, JointRows.JACOBIAN_B + 1)
				+ wbz * field(packed, base, JointRows.JACOBIAN_B + 2) + wax * field(packed, base, JointRows.JACOBIAN_A)
				+ way * field(packed, base, JointRows.JACOBIAN_A + 1) + waz * field(packed, base, JointRows.JACOBIAN_A + 2);
			var old = field(packed, base, JointRows.IMPULSE);
			var next = old
				+ field(packed, base, JointRows.TARGET)
				+ (field(packed, base, JointRows.GAIN) * speed + field(packed, base, JointRows.DECAY) * old) * minusOne;
			var upper = field(packed, base, JointRows.UPPER);
			var lower = field(packed, base, JointRows.LOWER);
			next = Float32x4.select(next.gt(upper), upper, next);
			next = Float32x4.select(lower.gt(next), lower, next);
			next.store(packed, base + (JointRows.IMPULSE << 4));
			var delta = next + old * minusOne;
			var lx = dx * delta, ly = dy * delta, lz = dz * delta;
			vax = vax + lx * field(packed, base, JointRows.NEG_INV_MASS_A);
			vay = vay + ly * field(packed, base, JointRows.NEG_INV_MASS_A + 1);
			vaz = vaz + lz * field(packed, base, JointRows.NEG_INV_MASS_A + 2);
			vbx = vbx + lx * field(packed, base, JointRows.INV_MASS_B);
			vby = vby + ly * field(packed, base, JointRows.INV_MASS_B + 1);
			vbz = vbz + lz * field(packed, base, JointRows.INV_MASS_B + 2);
			wax = wax + field(packed, base, JointRows.RESPONSE_A) * delta;
			way = way + field(packed, base, JointRows.RESPONSE_A + 1) * delta;
			waz = waz + field(packed, base, JointRows.RESPONSE_A + 2) * delta;
			wbx = wbx + field(packed, base, JointRows.RESPONSE_B) * delta;
			wby = wby + field(packed, base, JointRows.RESPONSE_B + 1) * delta;
			wbz = wbz + field(packed, base, JointRows.RESPONSE_B + 2) * delta;
			level++;
		}

		vax.store(scratch, VEL_A);
		vay.store(scratch, VEL_A + 16);
		vaz.store(scratch, VEL_A + 32);
		wax.store(scratch, ANG_A);
		way.store(scratch, ANG_A + 16);
		waz.store(scratch, ANG_A + 32);
		vbx.store(scratch, VEL_B);
		vby.store(scratch, VEL_B + 16);
		vbz.store(scratch, VEL_B + 32);
		wbx.store(scratch, ANG_B);
		wby.store(scratch, ANG_B + 16);
		wbz.store(scratch, ANG_B + 32);
		// Static and kinematic bodies may repeat across lanes and are never written.
		var writeA = rows.rowWriteA, writeB = rows.rowWriteB;
		for (lane in 0...4) {
			var id = joints[batch * 4 + lane];
			if (id < 0)
				continue;
			var r = rows.jointStart[id];
			var o = lane << 2;
			if (writeA[r] != 0) {
				var a = bodyA[r];
				world.velX[a] = scratch.getF32(VEL_A + o);
				world.velY[a] = scratch.getF32(VEL_A + 16 + o);
				world.velZ[a] = scratch.getF32(VEL_A + 32 + o);
				world.angVelX[a] = scratch.getF32(ANG_A + o);
				world.angVelY[a] = scratch.getF32(ANG_A + 16 + o);
				world.angVelZ[a] = scratch.getF32(ANG_A + 32 + o);
			}
			if (writeB[r] != 0) {
				var b = bodyB[r];
				world.velX[b] = scratch.getF32(VEL_B + o);
				world.velY[b] = scratch.getF32(VEL_B + 16 + o);
				world.velZ[b] = scratch.getF32(VEL_B + 32 + o);
				world.angVelX[b] = scratch.getF32(ANG_B + o);
				world.angVelY[b] = scratch.getF32(ANG_B + 16 + o);
				world.angVelZ[b] = scratch.getF32(ANG_B + 32 + o);
			}
		}
	}
}
