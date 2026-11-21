package hxn.me.physics.island;

import hxn.me.physics.collision.NarrowPhase.ContactManifoldPool;
import hxn.me.physics.core.Handles.BodyType;
import hxn.Int32Buffer;

class ConstraintGraph {
	public static inline var SIMD_COLORS:Int = 23;
	public static inline var FALLBACK_COLOR:Int = 23;
	public static inline var COLOR_COUNT:Int = 24;

	public var colors:Int32Buffer;
	public var indices:Int32Buffer;
	public var counts:Int32Buffer;
	public var offsets:Int32Buffer;

	var usedColors:Int32Buffer;
	var cursors:Int32Buffer;

	public function new(bodyCapacity:Int, contactCapacity:Int) {
		colors = new Int32Buffer(contactCapacity < 4 ? 4 : contactCapacity);
		indices = new Int32Buffer(contactCapacity < 4 ? 4 : contactCapacity);
		counts = new Int32Buffer(COLOR_COUNT);
		offsets = new Int32Buffer(COLOR_COUNT);
		cursors = new Int32Buffer(COLOR_COUNT);
		usedColors = new Int32Buffer(bodyCapacity);
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
		colors = new Int32Buffer(cap);
		indices = new Int32Buffer(cap);
	}

	public function assign(contacts:ContactManifoldPool, bodyType:Int32Buffer, bodyCount:Int):Void {
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
