package hxn.me.physics.solver;

import ash.simd.Float32x4;
import ash.simd.Vec;
import hxn.me.math.Float32Bytes;

/**
 * Solves four independent contact rows at once: body velocities are gathered
 * once, the normal and both friction impulses update in vector registers, and
 * each dynamic body is written back once.
 *
 * A group may be partial or hold skipped rows: those lanes are masked, so
 * every row of a SIMD colour is solved with the same lane arithmetic however
 * rows are grouped, and a serial solve matches an island-parallel one.
 *
 * Only Float32x4's Haxe-inline operations (load, store, add, mul, gt, select)
 * appear here, so Ash can keep the temporaries in registers; square root and
 * division go through scratch slots.
 */
class SimdSolver4 {
	static inline var VEL_A = 0;
	static inline var ANG_A = 48;
	static inline var VEL_B = 96;
	static inline var ANG_B = 144;
	static inline var LENGTH = 192;
	static inline var LIMIT = 208;
	static inline var MASK = 224;
	static inline var OUT = 240;

	var scratch:Float32Bytes;

	public function new() {
		scratch = new Float32Bytes(256);
		scratch.clear(0, 256);
	}

	static inline function field(rows:Float32Bytes, stride:Int, field:Int, base:Int):Float32x4 {
		return Float32x4.load(rows, field * stride + base);
	}

	/**
	 * Stores a row field's four lanes, or only the live ones when lanes are
	 * masked: a masked lane may be another island's row, solved at the same
	 * time by another worker, so it is never written.
	 */
	inline function put(value:Float32x4, rows:Float32Bytes, at:Int, slot:Int, count:Int, skip:hxn.Int32Buffer, whole:Bool):Void {
		if (whole)
			value.store(rows, at);
		else {
			value.store(scratch, OUT);
			for (lane in 0...count)
				if (skip[slot + lane] == 0)
					rows.setF32(at + (lane << 2), scratch.getF32(OUT + (lane << 2)));
		}
	}

	/** Solves rows `slot` to `slot + count - 1`, at most four; rows past them and skipped rows are masked out. */
	public function solve(solver:SoftStepSolver, slot:Int, count:Int = 4):Void {
		var skip = solver.rowSkip;
		var world = solver.world;
		var bodyA = solver.rowBodyA, bodyB = solver.rowBodyB;
		var live = 0;
		for (lane in 0...4) {
			var o = lane << 2;
			if (lane >= count || skip[slot + lane] != 0) {
				// A masked lane gathers nothing and changes nothing.
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
				scratch.setF32(MASK + o, 0.0);
				continue;
			}
			live++;
			scratch.setF32(MASK + o, 1.0);
			var a = bodyA[slot + lane], b = bodyB[slot + lane];
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
		if (live == 0)
			return;
		var whole = live == 4;
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

		var rows = solver.rows, stride = solver.stride, base = slot << 2;
		var lanes = solver.lanes;
		var minusOne = Float32x4.load(lanes, 0),
			zero = Float32x4.load(lanes, 16);
		var one = Float32x4.load(lanes, 32);
		var active = Float32x4.load(scratch, MASK).gt(zero);
		var imax = field(rows, stride, SoftStepSolver.NEG_INV_MASS_A, base);
		var imay = field(rows, stride, SoftStepSolver.NEG_INV_MASS_A + 1, base);
		var imaz = field(rows, stride, SoftStepSolver.NEG_INV_MASS_A + 2, base);
		var imbx = field(rows, stride, SoftStepSolver.INV_MASS_B, base);
		var imby = field(rows, stride, SoftStepSolver.INV_MASS_B + 1, base);
		var imbz = field(rows, stride, SoftStepSolver.INV_MASS_B + 2, base);

		// Normal impulse.
		var nx = field(rows, stride, SoftStepSolver.NX, base);
		var ny = field(rows, stride, SoftStepSolver.NX + 1, base);
		var nz = field(rows, stride, SoftStepSolver.NX + 2, base);
		var block = SoftStepSolver.NORMAL_ROWS;
		var speed = (vbx
			+ vax * minusOne) * nx
			+ (vby + vay * minusOne) * ny
			+ (vbz + vaz * minusOne) * nz
			+ wbx * field(rows, stride, block + SoftStepSolver.JACOBIAN_B, base)
			+ wby * field(rows, stride, block + SoftStepSolver.JACOBIAN_B + 1, base)
			+ wbz * field(rows, stride, block + SoftStepSolver.JACOBIAN_B + 2, base)
			+ wax * field(rows, stride, block + SoftStepSolver.JACOBIAN_A, base)
			+ way * field(rows, stride, block + SoftStepSolver.JACOBIAN_A + 1, base)
			+ waz * field(rows, stride, block + SoftStepSolver.JACOBIAN_A + 2, base);
		var oldNormal = field(rows, stride, SoftStepSolver.IMPULSE_N, base);
		var candidate = oldNormal
			+ field(rows, stride, SoftStepSolver.NORMAL_TARGET, base)
			+ field(rows, stride, SoftStepSolver.NORMAL_GAIN, base) * speed * minusOne
			+ field(rows, stride, SoftStepSolver.NEG_IMPULSE_SCALE, base) * oldNormal;
		var normal = Float32x4.select(active, Float32x4.select(candidate.gt(zero), candidate, zero), oldNormal);
		put(normal, rows, SoftStepSolver.IMPULSE_N * stride + base, slot, count, skip, whole);
		var dn = normal + oldNormal * minusOne;
		vax = vax + nx * imax * dn;
		vay = vay + ny * imay * dn;
		vaz = vaz + nz * imaz * dn;
		vbx = vbx + nx * imbx * dn;
		vby = vby + ny * imby * dn;
		vbz = vbz + nz * imbz * dn;
		wax = wax + field(rows, stride, block + SoftStepSolver.RESPONSE_A, base) * dn;
		way = way + field(rows, stride, block + SoftStepSolver.RESPONSE_A + 1, base) * dn;
		waz = waz + field(rows, stride, block + SoftStepSolver.RESPONSE_A + 2, base) * dn;
		wbx = wbx + field(rows, stride, block + SoftStepSolver.RESPONSE_B, base) * dn;
		wby = wby + field(rows, stride, block + SoftStepSolver.RESPONSE_B + 1, base) * dn;
		wbz = wbz + field(rows, stride, block + SoftStepSolver.RESPONSE_B + 2, base) * dn;

		// Friction: both tangent speeds use the post-normal velocities.
		var dvx = vbx + vax * minusOne,
			dvy = vby + vay * minusOne,
			dvz = vbz + vaz * minusOne;
		var tx = field(rows, stride, SoftStepSolver.T1X, base);
		var ty = field(rows, stride, SoftStepSolver.T1X + 1, base);
		var tz = field(rows, stride, SoftStepSolver.T1X + 2, base);
		var ux = field(rows, stride, SoftStepSolver.T2X, base);
		var uy = field(rows, stride, SoftStepSolver.T2X + 1, base);
		var uz = field(rows, stride, SoftStepSolver.T2X + 2, base);
		var t1 = SoftStepSolver.TANGENT1_ROWS,
			t2 = SoftStepSolver.TANGENT2_ROWS;
		var speed1 = dvx * tx
			+ dvy * ty
			+ dvz * tz
			+ wbx * field(rows, stride, t1 + SoftStepSolver.JACOBIAN_B, base)
			+ wby * field(rows, stride, t1 + SoftStepSolver.JACOBIAN_B + 1, base)
			+ wbz * field(rows, stride, t1 + SoftStepSolver.JACOBIAN_B + 2, base)
			+ wax * field(rows, stride, t1 + SoftStepSolver.JACOBIAN_A, base)
			+ way * field(rows, stride, t1 + SoftStepSolver.JACOBIAN_A + 1, base)
			+ waz * field(rows, stride, t1 + SoftStepSolver.JACOBIAN_A + 2, base);
		var speed2 = dvx * ux
			+ dvy * uy
			+ dvz * uz
			+ wbx * field(rows, stride, t2 + SoftStepSolver.JACOBIAN_B, base)
			+ wby * field(rows, stride, t2 + SoftStepSolver.JACOBIAN_B + 1, base)
			+ wbz * field(rows, stride, t2 + SoftStepSolver.JACOBIAN_B + 2, base)
			+ wax * field(rows, stride, t2 + SoftStepSolver.JACOBIAN_A, base)
			+ way * field(rows, stride, t2 + SoftStepSolver.JACOBIAN_A + 1, base)
			+ waz * field(rows, stride, t2 + SoftStepSolver.JACOBIAN_A + 2, base);
		var old1 = field(rows, stride, SoftStepSolver.IMPULSE_T1, base);
		var old2 = field(rows, stride, SoftStepSolver.IMPULSE_T2, base);
		var mass1 = field(rows, stride, SoftStepSolver.TANGENT_MASS1, base);
		var mass2 = field(rows, stride, SoftStepSolver.TANGENT_MASS2, base);
		var next1 = Float32x4.select(mass1.gt(zero), old1 + speed1 * mass1 * minusOne, zero);
		var next2 = Float32x4.select(mass2.gt(zero), old2 + speed2 * mass2 * minusOne, zero);
		// Clamp to the Coulomb disk: scale by limit / length where length exceeds limit.
		var limit = field(rows, stride, SoftStepSolver.FRICTION, base) * normal;
		var lengthSq = next1 * next1 + next2 * next2;
		var over = lengthSq.gt(limit * limit);
		lengthSq.store(scratch, LENGTH);
		limit.store(scratch, LIMIT);
		Vec.f32x4Sqrt(scratch, LENGTH, scratch, LENGTH);
		Vec.f32x4Div(scratch, LIMIT, scratch, LIMIT, scratch, LENGTH);
		var scale = Float32x4.select(over, Float32x4.load(scratch, LIMIT), one);
		next1 = Float32x4.select(active, next1 * scale, old1);
		next2 = Float32x4.select(active, next2 * scale, old2);
		put(next1, rows, SoftStepSolver.IMPULSE_T1 * stride + base, slot, count, skip, whole);
		put(next2, rows, SoftStepSolver.IMPULSE_T2 * stride + base, slot, count, skip, whole);
		var d1 = next1 + old1 * minusOne, d2 = next2 + old2 * minusOne;
		vax = vax + (tx * d1 + ux * d2) * imax;
		vay = vay + (ty * d1 + uy * d2) * imay;
		vaz = vaz + (tz * d1 + uz * d2) * imaz;
		vbx = vbx + (tx * d1 + ux * d2) * imbx;
		vby = vby + (ty * d1 + uy * d2) * imby;
		vbz = vbz + (tz * d1 + uz * d2) * imbz;
		wax = wax + field(rows, stride, t1 + SoftStepSolver.RESPONSE_A, base) * d1 + field(rows, stride, t2 + SoftStepSolver.RESPONSE_A, base) * d2;
		way = way + field(rows, stride, t1 + SoftStepSolver.RESPONSE_A + 1, base) * d1 + field(rows, stride, t2 + SoftStepSolver.RESPONSE_A + 1, base) * d2;
		waz = waz + field(rows, stride, t1 + SoftStepSolver.RESPONSE_A + 2, base) * d1 + field(rows, stride, t2 + SoftStepSolver.RESPONSE_A + 2, base) * d2;
		wbx = wbx + field(rows, stride, t1 + SoftStepSolver.RESPONSE_B, base) * d1 + field(rows, stride, t2 + SoftStepSolver.RESPONSE_B, base) * d2;
		wby = wby + field(rows, stride, t1 + SoftStepSolver.RESPONSE_B + 1, base) * d1 + field(rows, stride, t2 + SoftStepSolver.RESPONSE_B + 1, base) * d2;
		wbz = wbz + field(rows, stride, t1 + SoftStepSolver.RESPONSE_B + 2, base) * d1 + field(rows, stride, t2 + SoftStepSolver.RESPONSE_B + 2, base) * d2;

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
		// Static and kinematic supports may repeat across lanes and are never written.
		var writeA = solver.rowWriteA, writeB = solver.rowWriteB;
		for (lane in 0...count) {
			var o = lane << 2;
			if (skip[slot + lane] != 0)
				continue;
			if (writeA[slot + lane] != 0) {
				var a = bodyA[slot + lane];
				world.velX[a] = scratch.getF32(VEL_A + o);
				world.velY[a] = scratch.getF32(VEL_A + 16 + o);
				world.velZ[a] = scratch.getF32(VEL_A + 32 + o);
				world.angVelX[a] = scratch.getF32(ANG_A + o);
				world.angVelY[a] = scratch.getF32(ANG_A + 16 + o);
				world.angVelZ[a] = scratch.getF32(ANG_A + 32 + o);
			}
			if (writeB[slot + lane] != 0) {
				var b = bodyB[slot + lane];
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
