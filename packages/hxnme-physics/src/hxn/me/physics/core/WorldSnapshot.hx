package hxn.me.physics.core;

import hxn.Float32Buffer;
import hxn.Float64Buffer;
import hxn.Int32Buffer;

/**
 * `WorldSnapshot` holds everything about a world that decides how it steps
 * next: bodies, shape settings, joints with their warm starts and drives,
 * contacts, the broadphase tree, sleep state, kinematic targets, and the
 * event sets of the last step. Restoring a snapshot and stepping gives
 * exactly the result of stepping on from the moment the snapshot was taken.
 *
 * ```haxe
 * var start = new WorldSnapshot();
 * start.save(world);
 * ...
 * start.restore(world);   // back to the moment of saving
 * ```
 *
 * The first save allocates the snapshot's storage. Later saves of the same
 * world, and every restore, copy into that storage. Each snapshot can also be
 * restored into another world built by the same calls, which is how many
 * copies of one environment start from one state.
 *
 * Collider geometry is not copied. If a shape was attached, destroyed or
 * reshaped after a snapshot was taken, the snapshot cannot be restored, and
 * `restore` throws. The world's island workers, if any, must be the same on
 * both sides, because they change the order in which contacts are solved.
 */
@:allow(hxn.me.physics.core.World)
@:allow(hxn.me.physics.core.WorldEvents)
@:allow(hxn.me.physics.core.ShapePairEvents)
@:allow(hxn.me.physics.collision.BroadPhase)
@:allow(hxn.me.physics.collision.ContactManifoldPool)
@:allow(hxn.me.physics.island.IslandManager)
@:allow(hxn.me.physics.joints.JointPool)
@:allow(hxn.me.physics.joints.HingeSolver)
@:allow(hxn.me.physics.joints.PrismaticSolver)
@:allow(hxn.me.physics.joints.WeldSolver)
@:allow(hxn.me.physics.joints.SphericalSolver)
class WorldSnapshot {
	/** Is true when the snapshot holds a state. */
	public var saved(default, null) = false;

	/** Holds the world's `structureVersion` at the time of the save. */
	public var structureVersion(default, null):Int = 0;

	var restoring = false;
	var bodyCapacity = 0;
	var shapeCapacity = 0;
	var jointCapacity = 0;
	// Each element type has one pool. The k-th buffer of a type sits at offset[k] in its pool and
	// holds length[k] entries. Saving lays the buffers out in visiting order, so a later save of the
	// same world reuses the space.
	var scalars = new Float64Buffer(64);
	var scalarAt = 0;
	var intPool = new Int32Buffer(0);
	var intOffset = new Int32Buffer(16);
	var intLength = new Int32Buffer(16);
	var intUsed = 0;
	var intAt = 0;
	var singlePool = new Float32Buffer(0);
	var singleOffset = new Int32Buffer(16);
	var singleLength = new Int32Buffer(16);
	var singleUsed = 0;
	var singleAt = 0;
	var doublePool = new Float64Buffer(0);
	var doubleOffset = new Int32Buffer(16);
	var doubleLength = new Int32Buffer(16);
	var doubleUsed = 0;
	var doubleAt = 0;
	var floatPool = new Float32Buffer(1);
	var floatCapacity = 1;
	var floatOffset = new Int32Buffer(16);
	var floatLength = new Int32Buffer(16);
	var floatUsed = 0;
	var floatAt = 0;

	public function new() {}

	/** Saves the world's state. */
	public function save(world:World):Void {
		restoring = false;
		begin();
		intUsed = 0;
		singleUsed = 0;
		doubleUsed = 0;
		floatUsed = 0;
		world.visitState(this);
		structureVersion = world.structureVersion;
		bodyCapacity = world.bodyCapacity;
		shapeCapacity = world.shapeCapacity;
		jointCapacity = world.joints.capacity;
		saved = true;
	}

	/** Puts the world back in the saved state. Throws if nothing was saved or the world's shapes differ. */
	public function restore(world:World):Void {
		if (!saved)
			throw 'Nothing has been saved in this snapshot';
		if (world.structureVersion != structureVersion)
			throw 'The world\'s shapes changed since this snapshot was saved (structure ${world.structureVersion}, snapshot $structureVersion)';
		// If the world has less room than the saved world, it gets that room. If it has more, it keeps
		// it, and the room that the snapshot did not cover is reset as new.
		world.reserve(bodyCapacity, shapeCapacity, jointCapacity);
		restoring = true;
		begin();
		world.visitState(this);
		world.afterRestore(bodyCapacity, shapeCapacity, jointCapacity);
	}

	/** Returns a JSON summary: whether it holds a state, the structure it was saved from, and how much it stores. */
	public function describe():String {
		var stored = intUsed * 4 + singleUsed * 4 + doubleUsed * 8 + floatUsed * 4;
		return '{"saved":$saved,"structureVersion":$structureVersion,"bodyCapacity":$bodyCapacity,"shapeCapacity":$shapeCapacity,'
			+ '"jointCapacity":$jointCapacity,"values":$scalarAt,"buffers":${intAt + singleAt + doubleAt + floatAt},"bytes":$stored}';
	}

	inline function begin():Void {
		scalarAt = 0;
		intAt = 0;
		singleAt = 0;
		doubleAt = 0;
		floatAt = 0;
	}

	// Saving and restoring share the calls below. Each owner visits its state in a fixed order, and
	// a value passes through `int`/`float`/`bool`, so the same line stores it or brings it back.

	function int(v:Int):Int
		return Std.int(float(v));

	function bool(v:Bool):Bool
		return float(v ? 1.0 : 0.0) != 0.0;

	function float(v:Float):Float {
		var i = scalarAt++;
		if (restoring)
			return scalars[i];
		if (i == scalars.length)
			scalars = grownFloats(scalars, i + 1);
		scalars[i] = v;
		return v;
	}

	/** Returns how many entries of a range to visit. Saving visits the saved count. Restoring visits the larger of the saved and live counts, so it clears the entries past a shrunken count. */
	inline function span(live:Int, restored:Int):Int
		return restoring && live > restored ? live : restored;

	function ints(a:Int32Buffer, n:Int):Void {
		var i = intAt++;
		if (restoring) {
			var m = intLength[i];
			if (m > 0)
				a.blit(0, intPool, intOffset[i], m);
			for (k in m...n)
				a[k] = 0;
			return;
		}
		if (i == intOffset.length) {
			intOffset = grownInts(intOffset, i + 1);
			intLength = grownInts(intLength, i + 1);
		}
		if (intUsed + n > intPool.length)
			intPool = grownInts(intPool, intUsed + n);
		if (n > 0)
			intPool.blit(intUsed, a, 0, n);
		intOffset[i] = intUsed;
		intLength[i] = n;
		intUsed += n;
	}

	function singles(a:Float32Buffer, n:Int):Void {
		var i = singleAt++;
		if (restoring) {
			var m = singleLength[i];
			if (m > 0)
				a.blit(0, singlePool, singleOffset[i], m);
			for (k in m...n)
				a[k] = 0.0;
			return;
		}
		if (i == singleOffset.length) {
			singleOffset = grownInts(singleOffset, i + 1);
			singleLength = grownInts(singleLength, i + 1);
		}
		if (singleUsed + n > singlePool.length) {
			var grown = new Float32Buffer(capacityFor(singlePool.length, singleUsed + n));
			if (singleUsed > 0)
				grown.blit(0, singlePool, 0, singleUsed);
			singlePool = grown;
		}
		if (n > 0)
			singlePool.blit(singleUsed, a, 0, n);
		singleOffset[i] = singleUsed;
		singleLength[i] = n;
		singleUsed += n;
	}

	function doubles(a:Float64Buffer, n:Int):Void {
		var i = doubleAt++;
		if (restoring) {
			var m = doubleLength[i];
			if (m > 0)
				a.blit(0, doublePool, doubleOffset[i], m);
			for (k in m...n)
				a[k] = 0.0;
			return;
		}
		if (i == doubleOffset.length) {
			doubleOffset = grownInts(doubleOffset, i + 1);
			doubleLength = grownInts(doubleLength, i + 1);
		}
		if (doubleUsed + n > doublePool.length)
			doublePool = grownFloats(doublePool, doubleUsed + n);
		if (n > 0)
			doublePool.blit(doubleUsed, a, 0, n);
		doubleOffset[i] = doubleUsed;
		doubleLength[i] = n;
		doubleUsed += n;
	}

	function floats(b:Float32Buffer, n:Int):Void {
		var i = floatAt++;
		if (restoring) {
			var m = floatLength[i];
			if (m > 0)
				b.blit(0, floatPool, floatOffset[i], m);
			if (n > m)
				b.fill(0, m, n - m);
			return;
		}
		if (i == floatOffset.length) {
			floatOffset = grownInts(floatOffset, i + 1);
			floatLength = grownInts(floatLength, i + 1);
		}
		if (floatUsed + n > floatCapacity) {
			floatCapacity = capacityFor(floatCapacity, floatUsed + n);
			var grown = new Float32Buffer(floatCapacity);
			if (floatUsed > 0)
				grown.blit(0, floatPool, 0, floatUsed);
			floatPool = grown;
		}
		if (n > 0)
			floatPool.blit(floatUsed, b, 0, n);
		floatOffset[i] = floatUsed;
		floatLength[i] = n;
		floatUsed += n;
	}

	static inline function capacityFor(current:Int, needed:Int):Int {
		var c = current * 2;
		return c > needed ? c : needed;
	}

	static function grownInts(a:Int32Buffer, needed:Int):Int32Buffer {
		var grown = new Int32Buffer(capacityFor(a.length, needed));
		if (a.length > 0)
			grown.blit(0, a, 0, a.length);
		return grown;
	}

	static function grownFloats(a:Float64Buffer, needed:Int):Float64Buffer {
		var grown = new Float64Buffer(capacityFor(a.length, needed));
		if (a.length > 0)
			grown.blit(0, a, 0, a.length);
		return grown;
	}

	/** Saves or restores a growable int array. Restoring returns a larger array when the saved array does not fit. */
	function growingInts(a:Int32Buffer, n:Int):Int32Buffer {
		if (restoring && intLength[intAt] > a.length) {
			var grown = new Int32Buffer(intLength[intAt]);
			grown.blit(0, a, 0, a.length);
			a = grown;
		}
		ints(a, n);
		return a;
	}
}
