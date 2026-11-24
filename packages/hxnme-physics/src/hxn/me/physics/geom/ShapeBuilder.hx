package hxn.me.physics.geom;

import hxn.me.physics.geom.ShapeDef;
import hxn.me.physics.geom.VertexPool;
import hxn.me.math.Vec3;

class ShapeBuilder {
	static function validate(radius:Float, depth:Float, localZ:Float, density:Float):Void {
		if (!Math.isFinite(radius) || !Math.isFinite(depth) || !Math.isFinite(localZ) || !Math.isFinite(density) || radius < 0.0 || depth < 0.0
			|| density < 0.0)
			throw 'Shape dimensions and density must be finite and nonnegative';
	}

	public static function makeHull(pool:VertexPool, vertices:Array<Vec3>, radius:Float = 0.01, localZ:Float = 0.0, density:Float = 1.0):ShapeDef {
		validate(radius, 0.0, localZ, density);
		ConvexHull.triangles(vertices);
		var offset = pool.allocateBlock(vertices.length);
		var values:Array<Single> = [];
		for (i in 0...vertices.length) {
			var v = vertices[i];
			pool.vx[offset + i] = v.x;
			pool.vy[offset + i] = v.y;
			pool.vz[offset + i] = v.z;
			values.push(v.x);
			values.push(v.y);
			values.push(v.z);
		}
		var def = new ShapeDef(ShapeKind.Hull, offset, vertices.length, 0.0, radius, localZ, density);
		def.bindVertices(pool, values);
		return def;
	}

	/** Throws unless `vertices` form a convex polygon in the local XY plane, in either winding order. */
	public static function checkPolygon(vertices:Array<Vec3>):Void {
		if (vertices == null || vertices.length < 3)
			throw 'Polygon needs at least three vertices';
		var winding = 0;
		for (i in 0...vertices.length) {
			var a = vertices[i];
			var b = vertices[(i + 1) % vertices.length];
			var c = vertices[(i + 2) % vertices.length];
			if (a == null || b == null || c == null)
				throw 'Polygon vertices must be non-null';
			if (!Math.isFinite(a.x) || !Math.isFinite(a.y) || !Math.isFinite(a.z) || Math.abs(a.z) > 1e-6)
				throw 'Polygon vertices must be finite and in the local XY plane';
			var cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
			if (Math.abs(cross) < 1e-8)
				throw 'Polygon has a degenerate edge';
			var turn = cross > 0 ? 1 : -1;
			if (winding == 0)
				winding = turn;
			else if (turn != winding)
				throw 'Polygon must be convex and ordered';
		}
	}

	/** Builds a convex XY polygon in either winding order. */
	public static function makePolygon(pool:VertexPool, vertices:Array<Vec3>, depth:Float = 0.0, radius:Float = 0.01, localZ:Float = 0.0,
			density:Float = 1.0):ShapeDef {
		validate(radius, depth, localZ, density);
		checkPolygon(vertices);
		var offset = pool.allocateBlock(vertices.length);
		var values:Array<Single> = [];
		for (i in 0...vertices.length) {
			var v = vertices[i];
			pool.vx[offset + i] = v.x;
			pool.vy[offset + i] = v.y;
			pool.vz[offset + i] = 0.0;
			values.push(v.x);
			values.push(v.y);
			values.push(0.0);
		}
		var def = new ShapeDef(ShapeKind.Polygon, offset, vertices.length, depth, radius, localZ, density);
		def.bindVertices(pool, values);
		return def;
	}

	// When depth == 0.0, this makes a 2D circle. When depth > 0.0, it makes a 3D cylinder or pill.
	public static inline function makeCircle(radius:Float, depth:Float = 0.0, localZ:Float = 0.0, density:Float = 1.0):ShapeDef {
		validate(radius, depth, localZ, density);
		return new ShapeDef(ShapeKind.Point, 0, 0, depth, radius, localZ, density);
	}

	// When depth == 0.0, this makes a 2D capsule or segment. When depth > 0.0, it makes a 3D
	// rounded wall or plate.
	public static function makeSegment(pool:VertexPool, ax:Float, ay:Float, bx:Float, by:Float, depth:Float = 0.0, radius:Float = 0.05, localZ:Float = 0.0,
			density:Float = 1.0):ShapeDef {
		validate(radius, depth, localZ, density);
		if (!Math.isFinite(ax) || !Math.isFinite(ay) || !Math.isFinite(bx) || !Math.isFinite(by))
			throw 'Segment endpoints must be finite';
		var offset = pool.allocateBlock(2);
		pool.vx[offset] = ax;
		pool.vy[offset] = ay;
		pool.vz[offset] = 0.0;
		pool.vx[offset + 1] = bx;
		pool.vy[offset + 1] = by;
		pool.vz[offset + 1] = 0.0;
		var def = new ShapeDef(ShapeKind.Segment, offset, 2, depth, radius, localZ, density);
		def.bindVertices(pool, [ax, ay, 0.0, bx, by, 0.0]);
		return def;
	}

	public static inline function makeCapsule(pool:VertexPool, ax:Float, ay:Float, bx:Float, by:Float, depth:Float = 0.0, radius:Float = 0.05,
			localZ:Float = 0.0, density:Float = 1.0):ShapeDef {
		return makeSegment(pool, ax, ay, bx, by, depth, radius, localZ, density);
	}

	// When depth == 0.0, this makes a 2D rectangle. When depth > 0.0, it makes a 3D box.
	public static function makeBox(pool:VertexPool, halfW:Float, halfH:Float, depth:Float = 0.0, radius:Float = 0.01, localZ:Float = 0.0,
			density:Float = 1.0):ShapeDef {
		validate(radius, depth, localZ, density);
		if (!Math.isFinite(halfW) || !Math.isFinite(halfH) || halfW <= 0.0 || halfH <= 0.0)
			throw 'Box half extents must be finite and positive';
		var offset = pool.allocateBlock(4);
		var values:Array<Single> = [
			-halfW, -halfH, 0.0,  halfW, -halfH, 0.0,
			 halfW,  halfH, 0.0, -halfW,  halfH, 0.0
		];
		for (i in 0...4) {
			pool.vx[offset + i] = values[i * 3];
			pool.vy[offset + i] = values[i * 3 + 1];
			pool.vz[offset + i] = 0.0;
		}
		var def = new ShapeDef(ShapeKind.Polygon, offset, 4, depth, radius, localZ, density);
		def.bindVertices(pool, values);
		return def;
	}
}
