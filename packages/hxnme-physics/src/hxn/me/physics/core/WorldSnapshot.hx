package hxn.me.physics.core;

import hxn.me.math.Simd.FloatBuffer;
import hl.NativeArray;

/**
 * Everything about a world that decides how it steps next: bodies, shapes'
 * settings, joints and their warm starts and drives, contacts, the
 * broadphase tree, sleep state, kinematic targets, and last step's event
 * sets. Restoring a snapshot and stepping gives exactly the result stepping
 * on from where it was taken would have.
 *
 * ```haxe
 * var start = new WorldSnapshot();
 * start.save(world);
 * ...
 * start.restore(world);   // back to the moment of saving
 * ```
 *
 * The first save allocates the snapshot's storage; later saves of the same
 * world, and every restore, copy into what is there. A snapshot can also be
 * restored into another world built by the same calls, which is how many
 * copies of one environment start from one state.
 *
 * Collider geometry is not copied: a snapshot taken before a shape was
 * attached, destroyed or reshaped cannot be restored after it, and `restore`
 * throws. The world's island workers, if any, must be the same on both
 * sides, since they change the order contacts are solved in.
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
	/** Whether the snapshot holds a state. */
	public var saved(default, null) = false;

	/** The world's `structureVersion` when it was saved. */
	public var structureVersion(default, null):Int = 0;

	var restoring = false;
	var bodyCapacity = 0;
	var shapeCapacity = 0;
	var jointCapacity = 0;
	// One pool per element type. The k-th buffer of a type sits at offset[k] in its pool and holds length[k]
	// entries; saving lays the buffers out in visiting order, so a later save of the same world reuses the space.
	var scalars = new NativeArray<Float>(64);
	var scalarAt = 0;
	var intPool = new NativeArray<Int>(0);
	var intOffset = new NativeArray<Int>(16);
	var intLength = new NativeArray<Int>(16);
	var intUsed = 0;
	var intAt = 0;
	var singlePool = new NativeArray<Single>(0);
	var singleOffset = new NativeArray<Int>(16);
	var singleLength = new NativeArray<Int>(16);
	var singleUsed = 0;
	var singleAt = 0;
	var doublePool = new NativeArray<Float>(0);
	var doubleOffset = new NativeArray<Int>(16);
	var doubleLength = new NativeArray<Int>(16);
	var doubleUsed = 0;
	var doubleAt = 0;
	var floatPool = new hl.Bytes(4);
	var floatCapacity = 1;
	var floatOffset = new NativeArray<Int>(16);
	var floatLength = new NativeArray<Int>(16);
	var floatUsed = 0;
	var floatAt = 0;

	public function new() {}

	/** Takes the world's state. */
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
		// A world with less room than the one saved is given it; one with more keeps it, and the room the snapshot did not cover is made as new.
		world.reserve(bodyCapacity, shapeCapacity, jointCapacity);
		restoring = true;
		begin();
		world.visitState(this);
		world.afterRestore(bodyCapacity, shapeCapacity, jointCapacity);
	}

	/** A JSON summary: whether it holds a state, the structure it was saved from, and how much it stores. */
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

	// The calls below are shared by saving and restoring: each owner visits its state in a fixed order, and a value
	// passes through `int`/`float`/`bool` so the same line stores it or brings it back.

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

	/** How many entries of a range to visit: the saved count when saving, and when restoring whichever of the saved and live counts is larger, so entries past a shrunken count are cleared. */
	inline function span(live:Int, restored:Int):Int
		return restoring && live > restored ? live : restored;

	function ints(a:NativeArray<Int>, n:Int):Void {
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

	function singles(a:NativeArray<Single>, n:Int):Void {
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
			var grown = new NativeArray<Single>(capacityFor(singlePool.length, singleUsed + n));
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

	function doubles(a:NativeArray<Float>, n:Int):Void {
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

	function floats(b:FloatBuffer, n:Int):Void {
		var i = floatAt++;
		var bytes:hl.Bytes = b;
		if (restoring) {
			var m = floatLength[i];
			if (m > 0)
				bytes.blit(0, floatPool, floatOffset[i] << 2, m << 2);
			if (n > m)
				bytes.fill(m << 2, (n - m) << 2, 0);
			return;
		}
		if (i == floatOffset.length) {
			floatOffset = grownInts(floatOffset, i + 1);
			floatLength = grownInts(floatLength, i + 1);
		}
		if (floatUsed + n > floatCapacity) {
			floatCapacity = capacityFor(floatCapacity, floatUsed + n);
			var grown = new hl.Bytes(floatCapacity << 2);
			if (floatUsed > 0)
				grown.blit(0, floatPool, 0, floatUsed << 2);
			floatPool = grown;
		}
		if (n > 0)
			floatPool.blit(floatUsed << 2, bytes, 0, n << 2);
		floatOffset[i] = floatUsed;
		floatLength[i] = n;
		floatUsed += n;
	}

	static inline function capacityFor(current:Int, needed:Int):Int {
		var c = current * 2;
		return c > needed ? c : needed;
	}

	static function grownInts(a:NativeArray<Int>, needed:Int):NativeArray<Int> {
		var grown = new NativeArray<Int>(capacityFor(a.length, needed));
		if (a.length > 0)
			grown.blit(0, a, 0, a.length);
		return grown;
	}

	static function grownFloats(a:NativeArray<Float>, needed:Int):NativeArray<Float> {
		var grown = new NativeArray<Float>(capacityFor(a.length, needed));
		if (a.length > 0)
			grown.blit(0, a, 0, a.length);
		return grown;
	}

	/** A growable int array: restoring returns a larger array when the saved one does not fit. */
	function growingInts(a:NativeArray<Int>, n:Int):NativeArray<Int> {
		if (restoring && intLength[intAt] > a.length) {
			var grown = new NativeArray<Int>(intLength[intAt]);
			grown.blit(0, a, 0, a.length);
			a = grown;
		}
		ints(a, n);
		return a;
	}
}
