package hxn.me.physics.island;

import hxn.me.physics.collision.NarrowPhase.ContactManifoldPool;
import hxn.me.physics.core.Handles.BodyType;
import hl.NativeArray;

class ConstraintGraph {
	public static inline var SIMD_COLORS:Int = 23;
	public static inline var FALLBACK_COLOR:Int = 23;
	public static inline var COLOR_COUNT:Int = 24;

	public var colors:NativeArray<Int>;
	public var indices:NativeArray<Int>;
	public var counts:NativeArray<Int>;
	public var offsets:NativeArray<Int>;

	var usedColors:NativeArray<Int>;
	var cursors:NativeArray<Int>;

	public function new(bodyCapacity:Int, contactCapacity:Int) {
		colors = new NativeArray<Int>(contactCapacity < 4 ? 4 : contactCapacity);
		indices = new NativeArray<Int>(contactCapacity < 4 ? 4 : contactCapacity);
		counts = new NativeArray<Int>(COLOR_COUNT);
		offsets = new NativeArray<Int>(COLOR_COUNT);
		cursors = new NativeArray<Int>(COLOR_COUNT);
		usedColors = new NativeArray<Int>(bodyCapacity);
	}

	/** Room for `n` bodies. */
	public function growBodies(n:Int):Void {
		if (n > usedColors.length)
			usedColors = hxn.me.math.Grow.ints(usedColors, usedColors.length, n);
	}

	/** Makes room for `n` contacts. */
	public function reserve(n:Int):Void {
		if (n <= colors.length)
			return;
		var cap = colors.length;
		while (cap < n)
			cap *= 2;
		colors = new NativeArray<Int>(cap);
		indices = new NativeArray<Int>(cap);
	}

	public function assign(contacts:ContactManifoldPool, bodyType:NativeArray<Int>, bodyCount:Int):Void {
		reserve(contacts.count);
		for (body in 0...bodyCount)
			usedColors[body] = 0;
		for (color in 0...COLOR_COUNT)
			counts[color] = 0;
		for (contact in 0...contacts.count) {
			var a = contacts.bodyA[contact], b = contacts.bodyB[contact];
			var maskA = bodyType[a] == BodyType.Dynamic ? usedColors[a] : 0;
			var maskB = bodyType[b] == BodyType.Dynamic ? usedColors[b] : 0;
			var used = maskA | maskB;
			var color = 0;
			while (color < SIMD_COLORS && (used & (1 << color)) != 0)
				color++;
			colors[contact] = color;
			counts[color]++;
			if (color < SIMD_COLORS) {
				var bit = 1 << color;
				if (bodyType[a] == BodyType.Dynamic)
					usedColors[a] |= bit;
				if (bodyType[b] == BodyType.Dynamic)
					usedColors[b] |= bit;
			}
		}
		var next = 0;
		for (color in 0...COLOR_COUNT) {
			offsets[color] = next;
			cursors[color] = next;
			next += counts[color];
		}
		// Stable placement keeps contacts within each color in broad-phase order.
		for (contact in 0...contacts.count) {
			var color = colors[contact];
			indices[cursors[color]++] = contact;
		}
	}
}
