package hxn.me.physics.joints;

import hxn.Float32Buffer;
import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.math.Float32Bytes;
import hxn.Int32Buffer;
import hxn.me.math.BufferArray;
#if (ash_simd && hl)
import hxn.me.physics.joints.JointSimd4;
#end

/**
 * `JointRows` holds the scalar constraint rows of every active joint, and
 * prepares them once per substep.
 *
 * During `prepare`, each joint kind turns its geometry into rows. The
 * iterations then solve the rows without reading body poses or inertia
 * again. Each row updates
 * its accumulated impulse as
 *
 *     impulse = clamp(impulse + target - gain * speed - decay * impulse, lower, upper)
 *
 * where speed is the relative velocity along the row's Jacobian. The rows of
 * one joint are contiguous, and they are solved in the order that the kind
 * emitted them.
 *
 * Joints are colored so that no dynamic body appears twice in a color. With SIMD,
 * every batchable joint of a color is solved in a batch of four. The rows of
 * each batch are copied lane by lane into a packed buffer, and empty lanes
 * pad the last batch. The other joints are solved one by one. With an island
 * partition, the batches are formed within each island. Each worker then
 * solves the batches of its own island, and every joint takes the same
 * arithmetic as in a serial solve.
 */
@:allow(hxn.me.physics.joints.JointSimd4)
class JointRows {
	// Both bodies share the linear direction of each row. The angular Jacobian and the
	// inverse-inertia response are stored for each body, negated for A.
	static inline var DIR = 0;
	static inline var NEG_INV_MASS_A = 3;
	static inline var INV_MASS_B = 6;
	static inline var JACOBIAN_A = 9;
	static inline var JACOBIAN_B = 12;
	static inline var RESPONSE_A = 15;
	static inline var RESPONSE_B = 18;
	static inline var TARGET = 21;
	static inline var GAIN = 22;
	static inline var DECAY = 23;
	static inline var LOWER = 24;
	static inline var UPPER = 25;
	static inline var IMPULSE = 26;
	// Holds the target for the relax pass. Velocity targets keep their target, and position
	// corrections have none.
	static inline var RELAX_TARGET = 27;
	static inline var ROW_BYTES = FIELDS * 4;

	/** Sets the most rows that any joint kind emits. */
	public static inline var MAX_PER_JOINT = 8;

	/** Marks the first of three rows whose impulses are clamped together by length. */
	static inline var NORM_BLOCK = 1;

	static inline var FIELDS = 28;

	/** Sets the bytes of one packed level in a `Float32Bytes`: every field for four lanes. */
	static inline var LEVEL_BYTES = FIELDS * 16;

	static inline var COLORS = 24;
	static inline var OVERFLOW_COLOR = 23;

	var world:World;
	var rows:Float32Bytes;
	var capacity:Int = 0;

	public var count(default, null):Int = 0;

	/** Counts the four-joint batches solved together in the current substep. */
	public var packedBatches(get, never):Int;

	inline function get_packedBatches():Int
		return scheduled ? batchTotal : 0;

	var rowBodyA:Int32Buffer;
	var rowBodyB:Int32Buffer;
	var rowWriteA:Int32Buffer;
	var rowWriteB:Int32Buffer;
	var rowBlock:Int32Buffer;
	var storeBuffer:BufferArray<Float32Buffer>;
	var storeIndex:Int32Buffer;
	var jointStart:Int32Buffer;
	var jointCount:Int32Buffer;
	// Lists the joints with rows in this substep, in emission order, and whether each has a norm
	// block.
	var emitted:Int32Buffer;
	var emittedCount:Int = 0;
	var hasBlock:Int32Buffer;
	// The color schedule is built on the first solve of a substep.
	var scheduled:Bool = false;
	// Is true once batches are solved from the packed buffer, which then holds their impulses.
	var packedSolved:Bool = false;
	var usedColors:Int32Buffer;
	var jointColor:Int32Buffer;
	var colorCounts:Int32Buffer;
	var scalarOffset:Int32Buffer;
	var scalarCount:Int32Buffer;
	var scalarJoints:Int32Buffer;
	var batchOffset:Int32Buffer;
	var batchCount:Int32Buffer;
	var batchCursor:Int32Buffer;
	var batchTotal:Int = 0;
	var batchJoint:Int32Buffer;
	var batchLevelStart:Int32Buffer;
	var batchLevels:Int32Buffer;
	var packed:Float32Bytes;
	var packedLevels:Int = 0;
	// These fields hold the island partition that batches are formed within, or null for one
	// group, then the group of each joint, then the batches of each (color, group).
	var partition:Null<hxn.me.physics.island.IslandPartition>;
	var jointGroup:Int32Buffer;
	var groupBatchStart:Int32Buffer;
	var groupBatchCount:Int32Buffer;
	var groupCursor:Int32Buffer;
	var groups = 1;
	#if (ash_simd && hl)
	var simd:JointSimd4;
	var workerSimd:Array<JointSimd4> = [];
	#end

	// Holds the body data of the joint that is being prepared.
	var a:Int;
	var b:Int;
	var writeA:Int;
	var writeB:Int;
	var max:Float;
	var may:Float;
	var maz:Float;
	var mbx:Float;
	var mby:Float;
	var mbz:Float;
	var axx:Float;
	var ayy:Float;
	var azz:Float;
	var axy:Float;
	var axz:Float;
	var ayz:Float;
	var bxx:Float;
	var byy:Float;
	var bzz:Float;
	var bxy:Float;
	var bxz:Float;
	var byz:Float;

	public function new(world:World, jointCapacity:Int) {
		this.world = world;
		jointStart = new Int32Buffer(jointCapacity);
		jointCount = new Int32Buffer(jointCapacity);
		emitted = new Int32Buffer(jointCapacity);
		hasBlock = new Int32Buffer(jointCapacity);
		jointColor = new Int32Buffer(jointCapacity);
		usedColors = new Int32Buffer(world.bodyCapacity);
		colorCounts = new Int32Buffer(COLORS);
		scalarOffset = new Int32Buffer(COLORS);
		scalarCount = new Int32Buffer(COLORS);
		batchOffset = new Int32Buffer(COLORS);
		batchCount = new Int32Buffer(COLORS);
		batchCursor = new Int32Buffer(COLORS);
		scalarJoints = new Int32Buffer(jointCapacity);
		jointGroup = new Int32Buffer(jointCapacity);
		groupBatchStart = new Int32Buffer(COLORS);
		groupBatchCount = new Int32Buffer(COLORS);
		groupCursor = new Int32Buffer(COLORS);
		// Partial batches can leave every group of every color one batch more than a quarter of the joints.
		var batches = (jointCapacity >> 2) + jointCapacity + 1;
		batchJoint = new Int32Buffer(batches * 4);
		batchLevelStart = new Int32Buffer(batches);
		batchLevels = new Int32Buffer(batches);
		packed = new Float32Bytes(LEVEL_BYTES * 16);
		packedLevels = 16;
		#if (ash_simd && hl)
		simd = new JointSimd4();
		#end
		reserve(64);
	}

	function reserve(rowCapacity:Int):Void {
		if (rowCapacity <= capacity)
			return;
		var next = capacity == 0 ? rowCapacity : capacity;
		while (next < rowCapacity)
			next <<= 1;
		var grown = new Float32Bytes(next * ROW_BYTES);
		grown.clear(0, next * ROW_BYTES);
		var bodyA = new Int32Buffer(next),
			bodyB = new Int32Buffer(next);
		var writeA = new Int32Buffer(next),
			writeB = new Int32Buffer(next);
		var block = new Int32Buffer(next),
			index = new Int32Buffer(next);
		var buffers = new BufferArray<Float32Buffer>(next);
		// Rows are rebuilt every substep, so growing only needs fresh storage.
		rows = grown;
		rowBodyA = bodyA;
		rowBodyB = bodyB;
		rowWriteA = writeA;
		rowWriteB = writeB;
		rowBlock = block;
		storeIndex = index;
		storeBuffer = buffers;
		capacity = next;
	}

	/** Starts a substep's rows for up to `joints` joints. */
	public function reset(joints:Int):Void {
		reserve(joints * MAX_PER_JOINT);
		count = 0;
		emittedCount = 0;
		scheduled = false;
		packedSolved = false;
	}

	public function skip(id:Int):Void {
		jointStart[id] = count;
		jointCount[id] = 0;
	}

	public function begin(id:Int, bodyA:Int, bodyB:Int):Void {
		jointStart[id] = count;
		emitted[emittedCount++] = id;
		hasBlock[id] = 0;
		a = bodyA;
		b = bodyB;
		var w = world;
		writeA = w.bodyType[a] == BodyType.Dynamic ? 1 : 0;
		writeB = w.bodyType[b] == BodyType.Dynamic ? 1 : 0;
		if (writeA != 0) {
			max = w.invMassX[a];
			may = w.invMassY[a];
			maz = w.invMassZ[a];
			axx = w.invIxx[a];
			ayy = w.invIyy[a];
			azz = w.invIzz[a];
			axy = w.invIxy[a];
			axz = w.invIxz[a];
			ayz = w.invIyz[a];
		} else {
			max = may = maz = 0.0;
			axx = ayy = azz = axy = axz = ayz = 0.0;
		}
		if (writeB != 0) {
			mbx = w.invMassX[b];
			mby = w.invMassY[b];
			mbz = w.invMassZ[b];
			bxx = w.invIxx[b];
			byy = w.invIyy[b];
			bzz = w.invIzz[b];
			bxy = w.invIxy[b];
			bxz = w.invIxz[b];
			byz = w.invIyz[b];
		} else {
			mbx = mby = mbz = 0.0;
			bxx = byy = bzz = bxy = bxz = byz = 0.0;
		}
	}

	public function end(id:Int):Void {
		jointCount[id] = count - jointStart[id];
	}

	inline function put(base:Int, field:Int, value:Float):Void {
		rows.setF32(base + (field << 2), value);
	}

	/**
	 * Adds a row along linear direction `d` at lever arms `rA` and `rB` from the
	 * bodies' centers of mass. Returns the row's inverse effective mass. Finish
	 * the row with `set`.
	 */
	public function linear(dx:Float, dy:Float, dz:Float, rax:Float, ray:Float, raz:Float, rbx:Float, rby:Float, rbz:Float):Float {
		var jax = ray * dz - raz * dy,
			jay = raz * dx - rax * dz,
			jaz = rax * dy - ray * dx;
		var jbx = rby * dz - rbz * dy,
			jby = rbz * dx - rbx * dz,
			jbz = rbx * dy - rby * dx;
		return addRow(dx, dy, dz, jax, jay, jaz, jbx, jby, jbz);
	}

	/** Adds a purely angular row about `axis`. Returns its inverse effective mass. */
	public function angular(x:Float, y:Float, z:Float):Float {
		return addRow(0.0, 0.0, 0.0, x, y, z, x, y, z);
	}

	function addRow(dx:Float, dy:Float, dz:Float, jax:Float, jay:Float, jaz:Float, jbx:Float, jby:Float, jbz:Float):Float {
		var r = count++;
		var base = r * ROW_BYTES;
		var iax = axx * jax + axy * jay + axz * jaz;
		var iay = axy * jax + ayy * jay + ayz * jaz;
		var iaz = axz * jax + ayz * jay + azz * jaz;
		var ibx = bxx * jbx + bxy * jby + bxz * jbz;
		var iby = bxy * jbx + byy * jby + byz * jbz;
		var ibz = bxz * jbx + byz * jby + bzz * jbz;
		put(base, DIR, dx);
		put(base, DIR + 1, dy);
		put(base, DIR + 2, dz);
		put(base, NEG_INV_MASS_A, -max);
		put(base, NEG_INV_MASS_A + 1, -may);
		put(base, NEG_INV_MASS_A + 2, -maz);
		put(base, INV_MASS_B, mbx);
		put(base, INV_MASS_B + 1, mby);
		put(base, INV_MASS_B + 2, mbz);
		put(base, JACOBIAN_A, -jax);
		put(base, JACOBIAN_A + 1, -jay);
		put(base, JACOBIAN_A + 2, -jaz);
		put(base, JACOBIAN_B, jbx);
		put(base, JACOBIAN_B + 1, jby);
		put(base, JACOBIAN_B + 2, jbz);
		put(base, RESPONSE_A, -iax);
		put(base, RESPONSE_A + 1, -iay);
		put(base, RESPONSE_A + 2, -iaz);
		put(base, RESPONSE_B, ibx);
		put(base, RESPONSE_B + 1, iby);
		put(base, RESPONSE_B + 2, ibz);
		rowBodyA[r] = a;
		rowBodyB[r] = b;
		rowWriteA[r] = writeA;
		rowWriteB[r] = writeB;
		rowBlock[r] = 0;
		return dx * dx * (max + mbx)
			+ dy * dy * (may + mby)
			+ dz * dz * (maz + mbz)
			+ jax * iax
			+ jay * iay
			+ jaz * iaz
			+ jbx * ibx
			+ jby * iby
			+ jbz * ibz;
	}

	/**
	 * Sets the update coefficients of the row just added. Its accumulated
	 * impulse lives in `store[index]`, which warm-starts the row and receives
	 * the result in `storeImpulses`.
	 */
	public function set(target:Float, gain:Float, decay:Float, lower:Float, upper:Float, store:Float32Buffer, index:Int):Void {
		var r = count - 1;
		var base = r * ROW_BYTES;
		put(base, TARGET, target);
		put(base, GAIN, gain);
		put(base, DECAY, decay);
		put(base, RELAX_TARGET, target);
		put(base, LOWER, lower);
		put(base, UPPER, upper);
		put(base, IMPULSE, store[index]);
		storeBuffer[r] = store;
		storeIndex[r] = index;
	}

	/**
	 * Sets up the common equality row: impulse += -mass * (speed + bias + gamma * impulse).
	 * The bias of each rigid row only corrects position, so the relax pass drops it. The bias of a
	 * soft row is its spring.
	 */
	public inline function setEquality(mass:Float, bias:Float, gamma:Float, store:Float32Buffer, index:Int):Void {
		set(-mass * bias, mass, mass * gamma, Math.NEGATIVE_INFINITY, Math.POSITIVE_INFINITY, store, index);
		if (gamma == 0.0)
			relaxWithout();
	}

	/** Marks the row just added as a position correction, which the relax pass solves with no target. */
	public inline function relaxWithout():Void {
		put((count - 1) * ROW_BYTES, RELAX_TARGET, 0.0);
	}

	/**
	 * Switches every row to its relax target, for the pass after bodies move
	 * that takes position corrections back out of the velocities.
	 */
	public function relax():Void {
		for (r in 0...count) {
			var base = r * ROW_BYTES;
			rows.setF32(base + (TARGET << 2), rows.getF32(base + (RELAX_TARGET << 2)));
		}
		if (!scheduled || batchTotal == 0)
			return;
		for (batch in 0...batchTotal) {
			var start = batchLevelStart[batch];
			for (lane in 0...4) {
				var id = batchJoint[batch * 4 + lane];
				if (id < 0)
					continue;
				var first = jointStart[id];
				for (level in 0...jointCount[id])
					packed.setF32((start + level) * LEVEL_BYTES + (TARGET << 4) + (lane << 2), rows.getF32((first + level) * ROW_BYTES + (RELAX_TARGET << 2)));
			}
		}
	}

	/** Keeps scalar and packed impulses consistent when restarting the velocity solve. */
	public function clearCorrectionImpulses(mask:Int32Buffer):Void {
		for (r in 0...count)
			if (mask[rowBodyA[r]] != 0 || mask[rowBodyB[r]] != 0)
				rows.setF32(r * ROW_BYTES + (IMPULSE << 2), 0.0);
		for (batch in 0...batchTotal) {
			var start = batchLevelStart[batch];
			for (lane in 0...4) {
				var id = batchJoint[batch * 4 + lane];
				if (id < 0)
					continue;
				var first = jointStart[id];
				if (mask[rowBodyA[first]] == 0 && mask[rowBodyB[first]] == 0)
					continue;
				for (level in 0...jointCount[id])
					packed.setF32((start + level) * LEVEL_BYTES + (IMPULSE << 4) + (lane << 2), 0.0);
			}
		}
	}

	/** Groups the last three rows so their combined impulse is clamped to `limit` by length. */
	public function normBlock(limit:Float):Void {
		var first = count - 3;
		rowBlock[first] = NORM_BLOCK;
		hasBlock[emitted[emittedCount - 1]] = 1;
		put(first * ROW_BYTES, UPPER, limit);
	}

	/** Applies stored impulses, then colors the joints and packs batches from the warm-started rows. */
	public function warmStart():Void {
		var rows = this.rows;
		for (r in 0...count) {
			var impulse:Float = rows.getF32(r * ROW_BYTES + (IMPULSE << 2));
			if (impulse != 0.0)
				apply(r, impulse);
		}
		schedule();
	}

	/**
	 * Sorts joint ids by color, keeping the serial solve's color sequence for
	 * an island task. Joints of one color share no dynamic body, so order
	 * within a color does not change the result.
	 */
	public function sortByColor(ids:Int32Buffer, start:Int, count:Int):Void {
		for (i in start + 1...start + count) {
			var id = ids[i], color = jointColor[id];
			var j = i - 1;
			while (j >= start && jointColor[ids[j]] > color) {
				ids[j + 1] = ids[j];
				j--;
			}
			ids[j + 1] = id;
		}
	}

	/** Forms the next schedule's batches within the islands of `partition`, or across all joints when null. */
	public function usePartition(partition:Null<hxn.me.physics.island.IslandPartition>):Void {
		this.partition = partition;
	}

	/** Gives each island worker its own batch kernel. */
	public function configureWorkers(count:Int):Void {
		#if (ash_simd && hl)
		while (workerSimd.length < count)
			workerSimd.push(new JointSimd4());
		#end
	}

	/**
	 * Solves the joints of island task `task` once, color by color as the
	 * serial solve does: the island's batches of each color, then its joints
	 * that are not batched. `ids` from `start` holds the task's joints sorted
	 * by color.
	 */
	public function solveTask(task:Int, ids:Int32Buffer, start:Int, count:Int, worker:Int):Void {
		if (!scheduled)
			schedule();
		packedSolved = true;
		var p = start, end = start + count;
		for (color in 0...COLORS) {
			#if (ash_simd && hl)
			var at = color * groups + task;
			var first = groupBatchStart[at];
			for (batch in first...first + groupBatchCount[at])
				workerSimd[worker].solve(this, batch);
			#end
			while (p < end && jointColor[ids[p]] == color) {
				var id = ids[p++];
				if (!batchable(id))
					solveJoint(id);
			}
		}
	}

	/** Solves every joint once, color by color. Four-joint batches use SIMD where it is available. */
	public function solveAll():Void {
		if (!scheduled)
			schedule();
		packedSolved = true;
		for (color in 0...COLORS) {
			#if (ash_simd && hl)
			var first = batchOffset[color];
			for (batch in first...first + batchCount[color])
				simd.solve(this, batch);
			#end
			var start = scalarOffset[color];
			for (i in start...start + scalarCount[color])
				solveJoint(scalarJoints[i]);
		}
	}

	/**
	 * Colors the substep's joints and lays out batches. Rows are packed after
	 * warm starting, so packed impulses start from the warm-started values.
	 */
	function schedule():Void {
		scheduled = true;
		for (color in 0...COLORS) {
			colorCounts[color] = 0;
			batchCount[color] = 0;
			scalarCount[color] = 0;
		}
		for (i in 0...emittedCount) {
			var r = jointStart[emitted[i]];
			usedColors[rowBodyA[r]] = 0;
			usedColors[rowBodyB[r]] = 0;
		}
		for (i in 0...emittedCount) {
			var id = emitted[i];
			var r = jointStart[id];
			var a = rowBodyA[r], b = rowBodyB[r];
			var used = (rowWriteA[r] != 0 ? usedColors[a] : 0) | (rowWriteB[r] != 0 ? usedColors[b] : 0);
			var color = 0;
			while (color < OVERFLOW_COLOR && (used & (1 << color)) != 0)
				color++;
			jointColor[id] = color;
			if (color < OVERFLOW_COLOR) {
				if (rowWriteA[r] != 0)
					usedColors[a] |= 1 << color;
				if (rowWriteB[r] != 0)
					usedColors[b] |= 1 << color;
			}
			if (batchable(id))
				colorCounts[color]++;
		}
		// Each joint's group is its island task, or one group for all.
		var p = partition;
		groups = p == null ? 1 : p.activeCount;
		for (i in 0...emittedCount)
			jointGroup[emitted[i]] = 0;
		if (p != null)
			for (t in 0...p.activeCount) {
				var task = p.tasks[t];
				for (k in task.jointStart...task.jointStart + task.jointCount)
					jointGroup[p.jointIndices[k]] = t;
			}
		var cells = COLORS * groups;
		if (groupBatchStart.length < cells) {
			groupBatchStart = new Int32Buffer(cells);
			groupBatchCount = new Int32Buffer(cells);
			groupCursor = new Int32Buffer(cells);
		}
		for (c in 0...cells) {
			groupBatchCount[c] = 0;
			groupCursor[c] = 0;
		}
		for (i in 0...emittedCount) {
			var id = emitted[i];
			if (batchable(id))
				groupBatchCount[jointColor[id] * groups + jointGroup[id]]++;
		}
		// Every batchable joint goes in a batch of its color and group, and empty lanes pad the last
		// batch. The other joints are solved alone.
		batchTotal = 0;
		for (color in 0...COLORS) {
			batchOffset[color] = batchTotal;
			batchCount[color] = 0;
			for (g in 0...groups) {
				var at = color * groups + g,
					n = (groupBatchCount[at] + 3) >> 2;
				groupBatchStart[at] = batchTotal;
				groupBatchCount[at] = n;
				for (k in batchTotal * 4...(batchTotal + n) * 4)
					batchJoint[k] = -1;
				batchTotal += n;
				batchCount[color] += n;
			}
		}
		for (i in 0...emittedCount) {
			var id = emitted[i];
			if (!batchable(id))
				scalarCount[jointColor[id]]++;
		}
		var scalarTotal = 0;
		for (color in 0...COLORS) {
			scalarOffset[color] = scalarTotal;
			scalarTotal += scalarCount[color];
			scalarCount[color] = 0;
		}
		var levels = 0;
		for (i in 0...emittedCount) {
			var id = emitted[i];
			var color = jointColor[id];
			if (batchable(id)) {
				var at = color * groups + jointGroup[id],
					slot = groupCursor[at]++;
				batchJoint[(groupBatchStart[at] + (slot >> 2)) * 4 + (slot & 3)] = id;
				continue;
			}
			scalarJoints[scalarOffset[color] + scalarCount[color]++] = id;
		}
		for (batch in 0...batchTotal) {
			var deepest = 0;
			for (lane in 0...4) {
				var id = batchJoint[batch * 4 + lane];
				if (id < 0)
					continue;
				var rowsInJoint = jointCount[id];
				if (rowsInJoint > deepest)
					deepest = rowsInJoint;
			}
			batchLevelStart[batch] = levels;
			batchLevels[batch] = deepest;
			levels += deepest;
		}
		if (batchTotal > 0)
			pack(levels);
	}

	inline function batchable(id:Int):Bool {
		#if (ash_simd && !solver_scalar_bench)
		return jointColor[id] < OVERFLOW_COLOR && hasBlock[id] == 0;
		#else
		return false;
		#end
	}

	/** Copies batched rows into lanes. Levels past a joint's last row stay zero and change nothing. */
	function pack(levels:Int):Void {
		if (levels > packedLevels) {
			while (packedLevels < levels)
				packedLevels <<= 1;
			packed = new Float32Bytes(LEVEL_BYTES * packedLevels);
		}
		packed.clear(0, LEVEL_BYTES * levels);
		for (batch in 0...batchTotal) {
			var start = batchLevelStart[batch];
			for (lane in 0...4) {
				var id = batchJoint[batch * 4 + lane];
				if (id < 0)
					continue;
				var first = jointStart[id];
				for (level in 0...jointCount[id]) {
					var source = (first + level) * ROW_BYTES;
					var target = (start + level) * LEVEL_BYTES + (lane << 2);
					for (field in 0...FIELDS)
						packed.setF32(target + (field << 4), rows.getF32(source + (field << 2)));
				}
			}
		}
	}

	/** Returns impulses solved in batches to their rows. */
	function unpack():Void {
		for (batch in 0...batchTotal) {
			var start = batchLevelStart[batch];
			for (lane in 0...4) {
				var id = batchJoint[batch * 4 + lane];
				if (id < 0)
					continue;
				var first = jointStart[id];
				for (level in 0...jointCount[id])
					rows.setF32((first + level) * ROW_BYTES + (IMPULSE << 2), packed.getF32((start + level) * LEVEL_BYTES + (IMPULSE << 4) + (lane << 2)));
			}
		}
	}

	public function solveJoint(id:Int):Void {
		var r = jointStart[id];
		var end = r + jointCount[id];
		while (r < end)
			r = solveRow(r);
	}

	/** Solves the row at `r` (or the block it starts) and returns the next row. */
	inline function solveRow(r:Int):Int {
		if (rowBlock[r] == NORM_BLOCK) {
			solveNormBlock(r);
			return r + 3;
		}
		var base = r * ROW_BYTES;
		var old:Float = rows.getF32(base + (IMPULSE << 2));
		var next = old
			+ rows.getF32(base + (TARGET << 2))
			- rows.getF32(base + (GAIN << 2)) * speed(r)
			- rows.getF32(base + (DECAY << 2)) * old;
		next = Math.max(rows.getF32(base + (LOWER << 2)), Math.min(rows.getF32(base + (UPPER << 2)), next));
		rows.setF32(base + (IMPULSE << 2), next);
		if (next != old)
			apply(r, next - old);
		return r + 1;
	}

	/** Solves a norm block. All three candidates use the velocities from before the block, then share one length clamp. */
	function solveNormBlock(r:Int):Void {
		var rows = this.rows;
		var b0 = r * ROW_BYTES, b1 = b0 + ROW_BYTES, b2 = b1 + ROW_BYTES;
		var s0 = speed(r), s1 = speed(r + 1), s2 = speed(r + 2);
		var o0:Float = rows.getF32(b0 + (IMPULSE << 2));
		var o1:Float = rows.getF32(b1 + (IMPULSE << 2));
		var o2:Float = rows.getF32(b2 + (IMPULSE << 2));
		var n0 = o0 + rows.getF32(b0 + (TARGET << 2)) - rows.getF32(b0 + (GAIN << 2)) * s0;
		var n1 = o1 + rows.getF32(b1 + (TARGET << 2)) - rows.getF32(b1 + (GAIN << 2)) * s1;
		var n2 = o2 + rows.getF32(b2 + (TARGET << 2)) - rows.getF32(b2 + (GAIN << 2)) * s2;
		var limit:Float = rows.getF32(b0 + (UPPER << 2));
		var length = Math.sqrt(n0 * n0 + n1 * n1 + n2 * n2);
		if (length > limit) {
			var scale = limit / length;
			n0 *= scale;
			n1 *= scale;
			n2 *= scale;
		}
		rows.setF32(b0 + (IMPULSE << 2), n0);
		rows.setF32(b1 + (IMPULSE << 2), n1);
		rows.setF32(b2 + (IMPULSE << 2), n2);
		if (n0 != o0)
			apply(r, n0 - o0);
		if (n1 != o1)
			apply(r + 1, n1 - o1);
		if (n2 != o2)
			apply(r + 2, n2 - o2);
	}

	function speed(r:Int):Float {
		var rows = this.rows, w = world;
		var base = r * ROW_BYTES;
		var a = rowBodyA[r], b = rowBodyB[r];
		return (w.velX[b]
			- w.velX[a]) * rows.getF32(base + (DIR << 2))
			+ (w.velY[b] - w.velY[a]) * rows.getF32(base + ((DIR + 1) << 2))
			+ (w.velZ[b] - w.velZ[a]) * rows.getF32(base + ((DIR + 2) << 2))
			+ w.angVelX[b] * rows.getF32(base + (JACOBIAN_B << 2))
				+ w.angVelY[b] * rows.getF32(base + ((JACOBIAN_B + 1) << 2))
					+ w.angVelZ[b] * rows.getF32(base + ((JACOBIAN_B + 2) << 2))
						+ w.angVelX[a] * rows.getF32(base + (JACOBIAN_A << 2))
							+ w.angVelY[a] * rows.getF32(base + ((JACOBIAN_A + 1) << 2))
								+ w.angVelZ[a] * rows.getF32(base + ((JACOBIAN_A + 2) << 2));
	}

	function apply(r:Int, impulse:Float):Void {
		var rows = this.rows, w = world;
		var base = r * ROW_BYTES;
		var x = rows.getF32(base + (DIR << 2)) * impulse;
		var y = rows.getF32(base + ((DIR + 1) << 2)) * impulse;
		var z = rows.getF32(base + ((DIR + 2) << 2)) * impulse;
		if (rowWriteA[r] != 0) {
			var a = rowBodyA[r];
			w.velX[a] += x * rows.getF32(base + (NEG_INV_MASS_A << 2));
			w.velY[a] += y * rows.getF32(base + ((NEG_INV_MASS_A + 1) << 2));
			w.velZ[a] += z * rows.getF32(base + ((NEG_INV_MASS_A + 2) << 2));
			w.angVelX[a] += rows.getF32(base + (RESPONSE_A << 2)) * impulse;
			w.angVelY[a] += rows.getF32(base + ((RESPONSE_A + 1) << 2)) * impulse;
			w.angVelZ[a] += rows.getF32(base + ((RESPONSE_A + 2) << 2)) * impulse;
		}
		if (rowWriteB[r] != 0) {
			var b = rowBodyB[r];
			w.velX[b] += x * rows.getF32(base + (INV_MASS_B << 2));
			w.velY[b] += y * rows.getF32(base + ((INV_MASS_B + 1) << 2));
			w.velZ[b] += z * rows.getF32(base + ((INV_MASS_B + 2) << 2));
			w.angVelX[b] += rows.getF32(base + (RESPONSE_B << 2)) * impulse;
			w.angVelY[b] += rows.getF32(base + ((RESPONSE_B + 1) << 2)) * impulse;
			w.angVelZ[b] += rows.getF32(base + ((RESPONSE_B + 2) << 2)) * impulse;
		}
	}

	/** Copies each row's impulse back to the joint kind that owns it. */
	public function storeImpulses():Void {
		if (packedSolved && batchTotal > 0)
			unpack();
		var rows = this.rows;
		for (r in 0...count) {
			var store = storeBuffer[r];
			store[storeIndex[r]] = rows.getF32(r * ROW_BYTES + (IMPULSE << 2));
		}
	}
}
