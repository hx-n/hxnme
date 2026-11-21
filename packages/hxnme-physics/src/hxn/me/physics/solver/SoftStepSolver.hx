package hxn.me.physics.solver;

import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.DoFMask;
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.physics.island.ConstraintGraph;
import hxn.me.physics.island.IslandPartition;
import hxn.me.physics.island.IslandPartition.IslandTask;
import hl.Bytes;
import hl.NativeArray;
#if ash_simd
import hxn.me.physics.solver.SimdSolver4;
#end

/**
 * Contact rows are prepared once per substep, while body poses are fixed, and
 * stored field-major in solve order: four consecutive rows of one color are
 * one SIMD batch and load as whole vectors.
 */
@:allow(hxn.me.physics.solver.SimdSolver4)
class SoftStepSolver {
	// Row fields. Each direction block holds the A Jacobian and A response negated,
	// so applying an impulse is a multiply-add on both bodies.
	static inline var NX = 0;
	static inline var T1X = 3;
	static inline var T2X = 6;
	static inline var NEG_INV_MASS_A = 9;
	static inline var INV_MASS_B = 12;
	static inline var NORMAL_ROWS = 15;
	static inline var TANGENT1_ROWS = 27;
	static inline var TANGENT2_ROWS = 39;
	static inline var JACOBIAN_A = 0;
	static inline var JACOBIAN_B = 3;
	static inline var RESPONSE_A = 6;
	static inline var RESPONSE_B = 9;
	static inline var NORMAL_GAIN = 51;
	static inline var NORMAL_TARGET = 52;
	static inline var TANGENT_MASS1 = 53;
	static inline var TANGENT_MASS2 = 54;
	static inline var FRICTION = 55;
	static inline var IMPULSE_N = 56;
	static inline var IMPULSE_T1 = 57;
	static inline var IMPULSE_T2 = 58;
	static inline var NEG_IMPULSE_SCALE = 59;
	static inline var NORMAL_MASS = 60;
	// Separating speed an impact should leave with, or zero.
	static inline var BOUNCE_SPEED = 61;
	static inline var FIELDS = 62;

	public var world:World;
	public var packedBatches(default, null):Int = 0;
	public var graph:ConstraintGraph;
	public var rowCount(default, null):Int = 0;

	#if ash_simd
	var simd:SimdSolver4;
	var workerSimd:Array<SimdSolver4> = [];
	#end
	var rows:Bytes;
	var stride:Int;
	var rowContact:NativeArray<Int>;
	var rowBodyA:NativeArray<Int>;
	var rowBodyB:NativeArray<Int>;
	var rowWriteA:NativeArray<Int>;
	var rowWriteB:NativeArray<Int>;
	// Rows without normal effective mass take the scalar path, which leaves them untouched.
	var rowSkip:NativeArray<Int>;
	// Lane constants for the SIMD kernel: -1, 0, 1.
	var lanes:Bytes;
	var partition:IslandPartition;
	var capacity:Int = 0;

	/** Rows start at room for `capacity` contacts and grow when a substep has more. */
	public function new(world:World, capacity:Int) {
		this.world = world;
		graph = new ConstraintGraph(world.bodyCapacity, capacity);
		#if ash_simd
		simd = new SimdSolver4();
		#end
		allocate(capacity < 4 ? 4 : capacity);
		lanes = new Bytes(48);
		for (lane in 0...4) {
			lanes.setF32(lane << 2, -1.0);
			lanes.setF32(16 + (lane << 2), 0.0);
			lanes.setF32(32 + (lane << 2), 1.0);
		}
	}

	function allocate(cap:Int):Void {
		capacity = cap;
		var bytes = FIELDS * ((((cap + 7) & ~7) + 4) << 2);
		rows = new Bytes(bytes);
		rows.fill(0, bytes, 0);
		rowContact = new NativeArray<Int>(cap);
		rowBodyA = new NativeArray<Int>(cap);
		rowBodyB = new NativeArray<Int>(cap);
		rowWriteA = new NativeArray<Int>(cap);
		rowWriteB = new NativeArray<Int>(cap);
		rowSkip = new NativeArray<Int>(cap);
	}

	/** Colors the current contacts; island planning reads the colors before `prepare`. */
	public function color():Void {
		graph.assign(world.contacts, world.bodyType, world.bodyCount);
	}

	/**
	 * Builds one row per solved contact, in graph order, or in the order of
	 * `islands` when the substep is dispatched to island workers.
	 */
	public function prepare(h:Single, islands:IslandPartition = null):Void {
		// Contacts are springs of a fixed frequency over the pair's effective mass, so a light body under a heavy one
		// sinks further. Against a static or kinematic body they are twice as stiff, which keeps a loaded foot flat.
		var hertz = Math.min(30.0, 0.25 / h);
		var omega = 2.0 * Math.PI * hertz, staticOmega = 4.0 * Math.PI * hertz;
		var a1 = 2.0 * omega + h * omega * omega,
			staticA1 = 2.0 * staticOmega + h * staticOmega * staticOmega;
		var impulseScale = 1.0 / (1.0 + h * a1),
			staticImpulseScale = 1.0 / (1.0 + h * staticA1);
		var massScale = h * a1 * impulseScale,
			staticMassScale = h * staticA1 * staticImpulseScale;
		var biasRate = omega / (2.0 + h * omega),
			staticBiasRate = staticOmega / (2.0 + h * staticOmega);
		partition = islands;
		var order = islands == null ? graph.indices : islands.contactIndices;
		var count = islands == null ? world.contacts.count : islands.contactCount;
		if (count > capacity) {
			var cap = capacity;
			while (cap < count)
				cap *= 2;
			allocate(cap);
		}
		rowCount = count;
		// Fields sit one stride apart. Sizing it to this substep keeps the rows
		// compact, and an odd multiple of 16 bytes keeps fields off one cache set.
		stride = (((count + 7) & ~7) + 4) << 2;
		var rows = this.rows, stride = this.stride;
		var contacts = world.contacts;
		var w = world;
		for (slot in 0...count) {
			var c = order[slot];
			var a = contacts.bodyA[c], b = contacts.bodyB[c];
			rowContact[slot] = c;
			rowBodyA[slot] = a;
			rowBodyB[slot] = b;
			var dynamicA = w.bodyType[a] == BodyType.Dynamic;
			var dynamicB = w.bodyType[b] == BodyType.Dynamic;
			rowWriteA[slot] = dynamicA ? 1 : 0;
			rowWriteB[slot] = dynamicB ? 1 : 0;
			var max:Float = 0.0,
				may:Float = 0.0,
				maz:Float = 0.0,
				mbx:Float = 0.0,
				mby:Float = 0.0,
				mbz:Float = 0.0;
			var axx:Float = 0.0,
				ayy:Float = 0.0,
				azz:Float = 0.0,
				axy:Float = 0.0,
				axz:Float = 0.0,
				ayz:Float = 0.0;
			var bxx:Float = 0.0,
				byy:Float = 0.0,
				bzz:Float = 0.0,
				bxy:Float = 0.0,
				bxz:Float = 0.0,
				byz:Float = 0.0;
			if (dynamicA) {
				max = w.invMassX[a];
				may = w.invMassY[a];
				maz = w.invMassZ[a];
				axx = w.invIxx[a];
				ayy = w.invIyy[a];
				azz = w.invIzz[a];
				axy = w.invIxy[a];
				axz = w.invIxz[a];
				ayz = w.invIyz[a];
			}
			if (dynamicB) {
				mbx = w.invMassX[b];
				mby = w.invMassY[b];
				mbz = w.invMassZ[b];
				bxx = w.invIxx[b];
				byy = w.invIyy[b];
				bzz = w.invIzz[b];
				bxy = w.invIxy[b];
				bxz = w.invIxz[b];
				byz = w.invIyz[b];
			}
			put(rows, stride, NEG_INV_MASS_A, slot, -max);
			put(rows, stride, NEG_INV_MASS_A + 1, slot, -may);
			put(rows, stride, NEG_INV_MASS_A + 2, slot, -maz);
			put(rows, stride, INV_MASS_B, slot, mbx);
			put(rows, stride, INV_MASS_B + 1, slot, mby);
			put(rows, stride, INV_MASS_B + 2, slot, mbz);

			var nx:Float = contacts.normalX[c],
				ny:Float = contacts.normalY[c],
				nz:Float = contacts.normalZ[c];
			var tx:Float, ty:Float, tz:Float, ux:Float, uy:Float, uz:Float;
			if (w.bodyDoF[a] == DoFMask.Planar && w.bodyDoF[b] == DoFMask.Planar) {
				tx = -ny;
				ty = nx;
				tz = 0.0;
				ux = uy = uz = 0.0;
			} else {
				if (nx * nx + ny * ny > nz * nz) {
					var scale = 1.0 / Math.sqrt(nx * nx + ny * ny);
					tx = -ny * scale;
					ty = nx * scale;
					tz = 0.0;
				} else {
					var scale = 1.0 / Math.sqrt(ny * ny + nz * nz);
					tx = 0.0;
					ty = -nz * scale;
					tz = ny * scale;
				}
				ux = ny * tz - nz * ty;
				uy = nz * tx - nx * tz;
				uz = nx * ty - ny * tx;
			}
			put(rows, stride, NX, slot, nx);
			put(rows, stride, NX + 1, slot, ny);
			put(rows, stride, NX + 2, slot, nz);
			put(rows, stride, T1X, slot, tx);
			put(rows, stride, T1X + 1, slot, ty);
			put(rows, stride, T1X + 2, slot, tz);
			put(rows, stride, T2X, slot, ux);
			put(rows, stride, T2X + 1, slot, uy);
			put(rows, stride, T2X + 2, slot, uz);

			var px:Float = contacts.pointX[c],
				py:Float = contacts.pointY[c],
				pz:Float = contacts.pointZ[c];
			var rax = px - w.worldCenterX[a],
				ray = py - w.worldCenterY[a],
				raz = pz - w.worldCenterZ[a];
			var rbx = px - w.worldCenterX[b],
				rby = py - w.worldCenterY[b],
				rbz = pz - w.worldCenterZ[b];
			var normalK = direction(rows, stride, slot, NORMAL_ROWS, nx, ny, nz, rax, ray, raz, rbx, rby, rbz, max, may, maz, mbx, mby, mbz, axx, ayy, azz,
				axy, axz, ayz, bxx, byy, bzz, bxy, bxz, byz);
			var tangentK1 = direction(rows, stride, slot, TANGENT1_ROWS, tx, ty, tz, rax, ray, raz, rbx, rby, rbz, max, may, maz, mbx, mby, mbz, axx, ayy,
				azz, axy, axz, ayz, bxx, byy, bzz, bxy, bxz, byz);
			var tangentK2 = direction(rows, stride, slot, TANGENT2_ROWS, ux, uy, uz, rax, ray, raz, rbx, rby, rbz, max, may, maz, mbx, mby, mbz, axx, ayy,
				azz, axy, axz, ayz, bxx, byy, bzz, bxy, bxz, byz);
			var normalMass = normalK > 0.0 ? 1.0 / normalK : 0.0;
			put(rows, stride, TANGENT_MASS1, slot, tangentK1 > 0.0 ? 1.0 / tangentK1 : 0.0);
			put(rows, stride, TANGENT_MASS2, slot, tangentK2 > 0.0 ? 1.0 / tangentK2 : 0.0);
			var shapeA = contacts.shapeA[c], shapeB = contacts.shapeB[c];
			put(rows, stride, FRICTION, slot, Math.sqrt(w.shapeFriction[shapeA] * w.shapeFriction[shapeB]));

			var bounce = 0.0;
			var oldNormal = contacts.normalImpulse[c];
			if (oldNormal == 0.0) {
				var speed = velocityAlong(slot, NX, NORMAL_ROWS);
				if (speed < -1.0)
					bounce = -Math.max(w.shapeRestitution[shapeA], w.shapeRestitution[shapeB]) * speed;
				if (-speed > w.events.impactThreshold)
					w.recordImpact(c, -speed);
			}
			var anchored = !dynamicA || !dynamicB;
			// Deep overlaps separate at no more than a few metres a second rather than flying apart.
			var separationBias = Math.min(3.0, (anchored ? staticBiasRate : biasRate) * Math.max(0.0, contacts.penetration[c] - 0.002));
			var gain = (anchored ? staticMassScale : massScale) * normalMass;
			put(rows, stride, NEG_IMPULSE_SCALE, slot, anchored ? -staticImpulseScale : -impulseScale);
			put(rows, stride, NORMAL_GAIN, slot, gain);
			put(rows, stride, NORMAL_TARGET, slot, gain * separationBias);
			put(rows, stride, NORMAL_MASS, slot, normalMass);
			put(rows, stride, BOUNCE_SPEED, slot, bounce);
			rowSkip[slot] = normalMass > 0.0 ? 0 : 1;
			put(rows, stride, IMPULSE_N, slot, oldNormal);
			put(rows, stride, IMPULSE_T1, slot, contacts.tangentImpulse1[c]);
			put(rows, stride, IMPULSE_T2, slot, contacts.tangentImpulse2[c]);
		}
		packedBatches = 0;
		// solver_scalar_bench keeps batch order but uses scalar lanes for differential checks.
		#if (ash_simd && !solver_scalar_bench)
		if (islands == null) {
			for (color in 0...ConstraintGraph.SIMD_COLORS)
				packedBatches += graph.counts[color] >> 2;
		} else {
			for (index in 0...islands.activeCount) {
				var task = islands.tasks[index];
				for (color in 0...ConstraintGraph.SIMD_COLORS)
					packedBatches += task.counts[color] >> 2;
			}
		}
		#end
	}

	static inline function put(rows:Bytes, stride:Int, field:Int, slot:Int, value:Float):Void {
		rows.setF32(field * stride + (slot << 2), value);
	}

	/** Stores Jacobians and inverse-inertia responses along one direction; returns its inverse effective mass. */
	static inline function direction(rows:Bytes, stride:Int, slot:Int, block:Int, x:Float, y:Float, z:Float, rax:Float, ray:Float, raz:Float, rbx:Float,
			rby:Float, rbz:Float, max:Float, may:Float, maz:Float, mbx:Float, mby:Float, mbz:Float, axx:Float, ayy:Float, azz:Float, axy:Float, axz:Float,
			ayz:Float, bxx:Float, byy:Float, bzz:Float, bxy:Float, bxz:Float, byz:Float):Float {
		var jax = ray * z - raz * y,
			jay = raz * x - rax * z,
			jaz = rax * y - ray * x;
		var jbx = rby * z - rbz * y,
			jby = rbz * x - rbx * z,
			jbz = rbx * y - rby * x;
		var iax = axx * jax + axy * jay + axz * jaz;
		var iay = axy * jax + ayy * jay + ayz * jaz;
		var iaz = axz * jax + ayz * jay + azz * jaz;
		var ibx = bxx * jbx + bxy * jby + bxz * jbz;
		var iby = bxy * jbx + byy * jby + byz * jbz;
		var ibz = bxz * jbx + byz * jby + bzz * jbz;
		put(rows, stride, block + JACOBIAN_A, slot, -jax);
		put(rows, stride, block + JACOBIAN_A + 1, slot, -jay);
		put(rows, stride, block + JACOBIAN_A + 2, slot, -jaz);
		put(rows, stride, block + JACOBIAN_B, slot, jbx);
		put(rows, stride, block + JACOBIAN_B + 1, slot, jby);
		put(rows, stride, block + JACOBIAN_B + 2, slot, jbz);
		put(rows, stride, block + RESPONSE_A, slot, -iax);
		put(rows, stride, block + RESPONSE_A + 1, slot, -iay);
		put(rows, stride, block + RESPONSE_A + 2, slot, -iaz);
		put(rows, stride, block + RESPONSE_B, slot, ibx);
		put(rows, stride, block + RESPONSE_B + 1, slot, iby);
		put(rows, stride, block + RESPONSE_B + 2, slot, ibz);
		return x * x * (max + mbx)
			+ y * y * (may + mby)
			+ z * z * (maz + mbz)
			+ jax * iax
			+ jay * iay
			+ jaz * iaz
			+ jbx * ibx
			+ jby * iby
			+ jbz * ibz;
	}

	public function warmStart():Void {
		var rows = this.rows, stride = this.stride;
		for (slot in 0...rowCount) {
			var normal = get(rows, stride, IMPULSE_N, slot);
			if (normal != 0.0)
				apply(slot, NX, NORMAL_ROWS, normal);
			var t1 = get(rows, stride, IMPULSE_T1, slot),
				t2 = get(rows, stride, IMPULSE_T2, slot);
			if (t1 != 0.0)
				apply(slot, T1X, TANGENT1_ROWS, t1);
			if (t2 != 0.0)
				apply(slot, T2X, TANGENT2_ROWS, t2);
		}
	}

	public function solve(iterations:Int):Void {
		for (iter in 0...iterations) {
			for (color in 0...ConstraintGraph.COLOR_COUNT) {
				var slot = graph.offsets[color];
				var end = slot + graph.counts[color];
				#if (ash_simd && !solver_scalar_bench)
				// Every row of a SIMD colour goes through the lanes, the last group masked, so grouping cannot change a row's arithmetic.
				if (color < ConstraintGraph.SIMD_COLORS) {
					while (slot < end) {
						simd.solve(this, slot, end - slot < 4 ? end - slot : 4);
						slot += 4;
					}
				}
				#end
				while (slot < end)
					solveRow(slot++);
			}
			if (world.joints.count > 0)
				for (sweep in 0...world.jointSweeps)
					world.joints.solveIteration();
		}
	}

	/**
	 * Turns every row rigid and unbiased for the relax pass, which removes the
	 * velocity the biased solve added to push overlaps apart.
	 */
	public function relax():Void {
		var rows = this.rows, stride = this.stride;
		for (slot in 0...rowCount) {
			put(rows, stride, NORMAL_TARGET, slot, 0.0);
			put(rows, stride, NORMAL_GAIN, slot, get(rows, stride, NORMAL_MASS, slot));
			put(rows, stride, NEG_IMPULSE_SCALE, slot, 0.0);
		}
	}

	/** Restarts loop contacts from the restored physical velocity, without correction impulses. */
	public function clearCorrectionImpulses(mask:NativeArray<Int>):Void {
		for (slot in 0...rowCount)
			if (mask[rowBodyA[slot]] != 0 || mask[rowBodyB[slot]] != 0) {
				put(rows, stride, IMPULSE_N, slot, 0.0);
				put(rows, stride, IMPULSE_T1, slot, 0.0);
				put(rows, stride, IMPULSE_T2, slot, 0.0);
			}
	}

	/** Gives each contact that was struck this substep and is still pressed its rebound speed. */
	public function applyRestitution():Void {
		var rows = this.rows, stride = this.stride;
		for (slot in 0...rowCount) {
			var bounce:Float = get(rows, stride, BOUNCE_SPEED, slot);
			var old:Float = get(rows, stride, IMPULSE_N, slot);
			if (bounce == 0.0 || old == 0.0 || rowSkip[slot] != 0)
				continue;
			var mass:Float = get(rows, stride, NORMAL_MASS, slot);
			var next = Math.max(0.0, old - mass * (velocityAlong(slot, NX, NORMAL_ROWS) - bounce));
			put(rows, stride, IMPULSE_N, slot, next);
			if (next != old)
				apply(slot, NX, NORMAL_ROWS, next - old);
		}
	}

	/** Copies accumulated impulses back to the manifold pool for the next substep's warm start. */
	public function storeImpulses():Void {
		var contacts = world.contacts, rows = this.rows, stride = this.stride;
		for (slot in 0...rowCount) {
			var c = rowContact[slot];
			contacts.normalImpulse[c] = get(rows, stride, IMPULSE_N, slot);
			contacts.tangentImpulse1[c] = get(rows, stride, IMPULSE_T1, slot);
			contacts.tangentImpulse2[c] = get(rows, stride, IMPULSE_T2, slot);
		}
	}

	public function configureIslandWorkers(count:Int):Void {
		#if ash_simd
		while (workerSimd.length < count)
			workerSimd.push(new SimdSolver4());
		#end
		world.joints.configureWorkers(count);
	}

	/** Solves one island task; its rows were laid out in partition order by `prepare`. */
	public function solveIsland(index:Int, task:IslandTask, iterations:Int, worker:Int):Void {
		for (iter in 0...iterations) {
			for (color in 0...ConstraintGraph.COLOR_COUNT) {
				var slot = task.offsets[color];
				var end = slot + task.counts[color];
				#if (ash_simd && !solver_scalar_bench)
				if (color < ConstraintGraph.SIMD_COLORS) {
					while (slot < end) {
						workerSimd[worker].solve(this, slot, end - slot < 4 ? end - slot : 4);
						slot += 4;
					}
				}
				#end
				while (slot < end)
					solveRow(slot++);
			}
			if (task.jointCount > 0)
				for (sweep in 0...world.jointSweeps)
					world.joints.solveTask(index, partition.jointIndices, task.jointStart, task.jointCount, worker);
		}
	}

	function solveRow(slot:Int):Void {
		if (rowSkip[slot] != 0)
			return;
		var rows = this.rows, stride = this.stride;
		var old:Float = get(rows, stride, IMPULSE_N, slot);
		var next = Math.max(0.0,
			old
			+ get(rows, stride, NORMAL_TARGET, slot)
			- get(rows, stride, NORMAL_GAIN, slot) * velocityAlong(slot, NX, NORMAL_ROWS)
			+ get(rows, stride, NEG_IMPULSE_SCALE, slot) * old);
		put(rows, stride, IMPULSE_N, slot, next);
		if (next != old)
			apply(slot, NX, NORMAL_ROWS, next - old);

		var t1Mass:Float = get(rows, stride, TANGENT_MASS1, slot),
			t2Mass:Float = get(rows, stride, TANGENT_MASS2, slot);
		var oldT1:Float = get(rows, stride, IMPULSE_T1, slot),
			oldT2:Float = get(rows, stride, IMPULSE_T2, slot);
		var nextT1 = t1Mass > 0.0 ? oldT1 - velocityAlong(slot, T1X, TANGENT1_ROWS) * t1Mass : 0.0;
		var nextT2 = t2Mass > 0.0 ? oldT2 - velocityAlong(slot, T2X, TANGENT2_ROWS) * t2Mass : 0.0;
		var limit = get(rows, stride, FRICTION, slot) * next;
		var length = Math.sqrt(nextT1 * nextT1 + nextT2 * nextT2);
		if (length > limit && length > 0.0) {
			var scale = limit / length;
			nextT1 *= scale;
			nextT2 *= scale;
		}
		put(rows, stride, IMPULSE_T1, slot, nextT1);
		put(rows, stride, IMPULSE_T2, slot, nextT2);
		if (nextT1 != oldT1)
			apply(slot, T1X, TANGENT1_ROWS, nextT1 - oldT1);
		if (nextT2 != oldT2)
			apply(slot, T2X, TANGENT2_ROWS, nextT2 - oldT2);
	}

	static inline function get(rows:Bytes, stride:Int, field:Int, slot:Int):Single {
		return rows.getF32(field * stride + (slot << 2));
	}

	function velocityAlong(slot:Int, axis:Int, block:Int):Float {
		var rows = this.rows, stride = this.stride, w = world;
		var a = rowBodyA[slot], b = rowBodyB[slot];
		return (w.velX[b]
			- w.velX[a]) * get(rows, stride, axis, slot)
			+ (w.velY[b] - w.velY[a]) * get(rows, stride, axis + 1, slot)
			+ (w.velZ[b] - w.velZ[a]) * get(rows, stride, axis + 2, slot)
			+ w.angVelX[b] * get(rows, stride, block + JACOBIAN_B, slot)
				+ w.angVelY[b] * get(rows, stride, block + JACOBIAN_B + 1, slot)
					+ w.angVelZ[b] * get(rows, stride, block + JACOBIAN_B + 2, slot)
						+ w.angVelX[a] * get(rows, stride, block + JACOBIAN_A, slot)
							+ w.angVelY[a] * get(rows, stride, block + JACOBIAN_A + 1, slot)
								+ w.angVelZ[a] * get(rows, stride, block + JACOBIAN_A + 2, slot);
	}

	function apply(slot:Int, axis:Int, block:Int, impulse:Float):Void {
		var rows = this.rows, stride = this.stride, w = world;
		var x = get(rows, stride, axis, slot) * impulse;
		var y = get(rows, stride, axis + 1, slot) * impulse;
		var z = get(rows, stride, axis + 2, slot) * impulse;
		if (rowWriteA[slot] != 0) {
			var a = rowBodyA[slot];
			w.velX[a] += x * get(rows, stride, NEG_INV_MASS_A, slot);
			w.velY[a] += y * get(rows, stride, NEG_INV_MASS_A + 1, slot);
			w.velZ[a] += z * get(rows, stride, NEG_INV_MASS_A + 2, slot);
			w.angVelX[a] += get(rows, stride, block + RESPONSE_A, slot) * impulse;
			w.angVelY[a] += get(rows, stride, block + RESPONSE_A + 1, slot) * impulse;
			w.angVelZ[a] += get(rows, stride, block + RESPONSE_A + 2, slot) * impulse;
		}
		if (rowWriteB[slot] != 0) {
			var b = rowBodyB[slot];
			w.velX[b] += x * get(rows, stride, INV_MASS_B, slot);
			w.velY[b] += y * get(rows, stride, INV_MASS_B + 1, slot);
			w.velZ[b] += z * get(rows, stride, INV_MASS_B + 2, slot);
			w.angVelX[b] += get(rows, stride, block + RESPONSE_B, slot) * impulse;
			w.angVelY[b] += get(rows, stride, block + RESPONSE_B + 1, slot) * impulse;
			w.angVelZ[b] += get(rows, stride, block + RESPONSE_B + 2, slot) * impulse;
		}
	}
}
