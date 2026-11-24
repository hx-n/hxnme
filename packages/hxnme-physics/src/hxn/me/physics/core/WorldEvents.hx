package hxn.me.physics.core;

import hxn.me.physics.core.Handles.ShapeId;
import hxn.Float64Buffer;
import hxn.Int32Buffer;

/**
 * `ShapePairEvents` lists the shape pairs that one step reports, each with
 * the user values of the two shapes. Pairs are ordered by shape slot, then
 * generation, so the order is the same however the step was solved.
 */
@:allow(hxn.me.physics.core.WorldEvents)
@:allow(hxn.me.physics.core.World)
class ShapePairEvents {
	public var count(default, null):Int = 0;

	var a:Int32Buffer;
	var b:Int32Buffer;
	var userA:Int32Buffer;
	var userB:Int32Buffer;

	public function new() {
		a = new Int32Buffer(16);
		b = new Int32Buffer(16);
		userA = new Int32Buffer(16);
		userB = new Int32Buffer(16);
	}

	public inline function shapeA(i:Int):ShapeId
		return a[i];

	public inline function shapeB(i:Int):ShapeId
		return b[i];

	public inline function userDataA(i:Int):Int
		return userA[i];

	public inline function userDataB(i:Int):Int
		return userB[i];

	function clear():Void
		count = 0;

	function push(shapeA:Int, shapeB:Int, dataA:Int, dataB:Int):Void {
		if (count == a.length) {
			var size = count * 2;
			a = WorldEvents.grow(a, size);
			b = WorldEvents.grow(b, size);
			userA = WorldEvents.grow(userA, size);
			userB = WorldEvents.grow(userB, size);
		}
		a[count] = shapeA;
		b[count] = shapeB;
		userA[count] = dataA;
		userB[count] = dataB;
		count++;
	}

	/** Sorts by pair and drops repeated pairs, keeping the first of each. */
	function sortUnique():Void {
		var gap = 1;
		while (gap * 3 + 1 < count)
			gap = gap * 3 + 1;
		while (gap > 0) {
			for (i in gap...count) {
				var ka = a[i], kb = b[i], ua = userA[i], ub = userB[i];
				var j = i;
				while (j >= gap && WorldEvents.comparePairs(a[j - gap], b[j - gap], ka, kb) > 0) {
					a[j] = a[j - gap];
					b[j] = b[j - gap];
					userA[j] = userA[j - gap];
					userB[j] = userB[j - gap];
					j -= gap;
				}
				a[j] = ka;
				b[j] = kb;
				userA[j] = ua;
				userB[j] = ub;
			}
			gap = Std.int(gap / 3);
		}
		var kept = 0;
		for (i in 0...count) {
			if (kept > 0 && a[kept - 1] == a[i] && b[kept - 1] == b[i])
				continue;
			a[kept] = a[i];
			b[kept] = b[i];
			userA[kept] = userA[i];
			userB[kept] = userB[i];
			kept++;
		}
		count = kept;
	}

	function visitState(s:WorldSnapshot):Void {
		var live = count;
		count = s.int(count);
		var n = s.span(live, count);
		a = s.growingInts(a, n);
		b = s.growingInts(b, n);
		userA = s.growingInts(userA, n);
		userB = s.growingInts(userB, n);
	}
}

/** `ImpactEvents` lists the fast new contacts from one step, at most one per shape pair: the one with the fastest approach. */
@:allow(hxn.me.physics.core.WorldEvents)
@:allow(hxn.me.physics.core.World)
class ImpactEvents extends ShapePairEvents {
	var speeds:Float64Buffer;
	var points:Float64Buffer;
	var normals:Float64Buffer;

	public function new() {
		super();
		speeds = new Float64Buffer(16);
		points = new Float64Buffer(48);
		normals = new Float64Buffer(48);
	}

	/** Returns the approach speed along the contact normal, positive, just before the contact was solved. */
	public inline function speed(i:Int):Float
		return speeds[i];

	public inline function pointX(i:Int):Float
		return points[i * 3];

	public inline function pointY(i:Int):Float
		return points[i * 3 + 1];

	public inline function pointZ(i:Int):Float
		return points[i * 3 + 2];

	/** Returns the contact normal, which points from shape A toward shape B. */
	public inline function normalX(i:Int):Float
		return normals[i * 3];

	public inline function normalY(i:Int):Float
		return normals[i * 3 + 1];

	public inline function normalZ(i:Int):Float
		return normals[i * 3 + 2];

	function pushImpact(shapeA:Int, shapeB:Int, dataA:Int, dataB:Int, approach:Float, px:Float, py:Float, pz:Float, nx:Float, ny:Float, nz:Float):Void {
		var i = count;
		push(shapeA, shapeB, dataA, dataB);
		if (i == speeds.length) {
			speeds = WorldEvents.growFloat(speeds, i * 2);
			points = WorldEvents.growFloat(points, i * 6);
			normals = WorldEvents.growFloat(normals, i * 6);
		}
		speeds[i] = approach;
		points[i * 3] = px;
		points[i * 3 + 1] = py;
		points[i * 3 + 2] = pz;
		normals[i * 3] = nx;
		normals[i * 3 + 1] = ny;
		normals[i * 3 + 2] = nz;
	}

	/** Sorts by pair, fastest first within a pair, and keeps the fastest impact of each pair. */
	function sortFastest():Void {
		var gap = 1;
		while (gap * 3 + 1 < count)
			gap = gap * 3 + 1;
		while (gap > 0) {
			for (i in gap...count) {
				var j = i;
				while (j >= gap) {
					var order = WorldEvents.comparePairs(a[j - gap], b[j - gap], a[j], b[j]);
					if (order < 0 || order == 0 && speeds[j - gap] >= speeds[j])
						break;
					swap(j - gap, j);
					j -= gap;
				}
			}
			gap = Std.int(gap / 3);
		}
		var kept = 0;
		for (i in 0...count) {
			if (kept > 0 && a[kept - 1] == a[i] && b[kept - 1] == b[i])
				continue;
			if (kept != i)
				copy(kept, i);
			kept++;
		}
		count = kept;
	}

	function swap(i:Int, j:Int):Void {
		var t = a[i];
		a[i] = a[j];
		a[j] = t;
		t = b[i];
		b[i] = b[j];
		b[j] = t;
		t = userA[i];
		userA[i] = userA[j];
		userA[j] = t;
		t = userB[i];
		userB[i] = userB[j];
		userB[j] = t;
		var f = speeds[i];
		speeds[i] = speeds[j];
		speeds[j] = f;
		for (k in 0...3) {
			f = points[i * 3 + k];
			points[i * 3 + k] = points[j * 3 + k];
			points[j * 3 + k] = f;
			f = normals[i * 3 + k];
			normals[i * 3 + k] = normals[j * 3 + k];
			normals[j * 3 + k] = f;
		}
	}

	function copy(dst:Int, src:Int):Void {
		a[dst] = a[src];
		b[dst] = b[src];
		userA[dst] = userA[src];
		userB[dst] = userB[src];
		speeds[dst] = speeds[src];
		for (k in 0...3) {
			points[dst * 3 + k] = points[src * 3 + k];
			normals[dst * 3 + k] = normals[src * 3 + k];
		}
	}
}

/**
 * `WorldEvents` reports what happened during the last `World.step`. Each
 * step refills the buffers, so read them after stepping and before the next
 * step.
 */
@:allow(hxn.me.physics.core.World)
@:allow(hxn.me.physics.core.ShapePairEvents)
class WorldEvents {
	/** Lists the sensor shapes that began to overlap another shape. Shape A is a sensor. */
	public var sensorBegins(default, null):ShapePairEvents;

	/** Lists the sensor overlaps that ended, including overlaps whose shape was destroyed or disabled. */
	public var sensorEnds(default, null):ShapePairEvents;

	/** Lists the solid shape pairs that began touching. */
	public var contactBegins(default, null):ShapePairEvents;

	/** Lists the solid shape pairs that stopped touching, including pairs whose shape was destroyed or disabled. */
	public var contactEnds(default, null):ShapePairEvents;

	/** Lists the new contacts that arrived faster than `impactThreshold`. */
	public var impacts(default, null):ImpactEvents;

	/** Sets the approach speed, in meters per second, that a new contact needs for the step to report it as an impact. */
	public var impactThreshold:Float = 1.0;

	// These fields hold the touching and overlapping pairs at the end of the previous step, and the
	// pairs that the current step gathers.
	var touching:ShapePairEvents;
	var touchingNext:ShapePairEvents;
	var overlapping:ShapePairEvents;
	var overlappingNext:ShapePairEvents;

	function new() {
		sensorBegins = new ShapePairEvents();
		sensorEnds = new ShapePairEvents();
		contactBegins = new ShapePairEvents();
		contactEnds = new ShapePairEvents();
		impacts = new ImpactEvents();
		touching = new ShapePairEvents();
		touchingNext = new ShapePairEvents();
		overlapping = new ShapePairEvents();
		overlappingNext = new ShapePairEvents();
	}

	static function grow(values:Int32Buffer, size:Int):Int32Buffer {
		var next = new Int32Buffer(size);
		next.blit(0, values, 0, values.length);
		return next;
	}

	static function growFloat(values:Float64Buffer, size:Int):Float64Buffer {
		var next = new Float64Buffer(size);
		next.blit(0, values, 0, values.length);
		return next;
	}

	static inline function key(handle:Int):Float {
		return (handle & 0xFFFFF) * 4096.0 + (handle >>> 20);
	}

	/** Orders pairs by slot of A, generation of A, then the same for B. */
	static function comparePairs(a1:Int, b1:Int, a2:Int, b2:Int):Int {
		var x = key(a1), y = key(a2);
		if (x != y)
			return x < y ? -1 : 1;
		x = key(b1);
		y = key(b2);
		return x < y ? -1 : (x > y ? 1 : 0);
	}

	function beginStep():Void {
		sensorBegins.clear();
		sensorEnds.clear();
		contactBegins.clear();
		contactEnds.clear();
		impacts.clear();
		touchingNext.clear();
		overlappingNext.clear();
	}

	/** Diffs a sorted current set against the previous one into begin and end events. */
	static function diff(previous:ShapePairEvents, current:ShapePairEvents, begins:ShapePairEvents, ends:ShapePairEvents):Void {
		var i = 0, j = 0;
		while (i < previous.count || j < current.count) {
			var order = i == previous.count ? 1 : (j == current.count ? -1 : comparePairs(previous.a[i], previous.b[i], current.a[j], current.b[j]));
			if (order < 0) {
				ends.push(previous.a[i], previous.b[i], previous.userA[i], previous.userB[i]);
				i++;
			} else if (order > 0) {
				begins.push(current.a[j], current.b[j], current.userA[j], current.userB[j]);
				j++;
			} else {
				i++;
				j++;
			}
		}
	}

	function finishStep():Void {
		touchingNext.sortUnique();
		diff(touching, touchingNext, contactBegins, contactEnds);
		var t = touching;
		touching = touchingNext;
		touchingNext = t;
		overlappingNext.sortUnique();
		diff(overlapping, overlappingNext, sensorBegins, sensorEnds);
		var o = overlapping;
		overlapping = overlappingNext;
		overlappingNext = o;
		impacts.sortFastest();
	}

	/** Visits the touching and overlapping sets of the last step for `WorldSnapshot`. The next step finds its begins and ends against these sets. */
	@:noCompletion public function visitState(s:WorldSnapshot):Void {
		impactThreshold = s.float(impactThreshold);
		touching.visitState(s);
		overlapping.visitState(s);
	}
}
