package hxn.me.physics.geom;

import hxn.me.math.Vec3;

enum abstract ShapeKind(Int) from Int to Int {
	var Point = 0; // 0 verts: 2D Circle (depth == 0) or 3D Cylinder/Sphere (depth > 0)
	var Segment = 1; // 2 verts: 2D Line/Capsule (depth == 0) or 3D Quad/Lozenge (depth > 0)
	var Polygon = 2; // N coplanar verts: 2D Polygon (depth == 0) or 3D Extruded Prism (depth > 0)
	var Hull = 3; // N volumetric 3D verts (intrinsic depth > 0)
}

private class VertexLease {
	public var pool:VertexPool;
	public var values:Array<Single>;
	public var generation:Int;

	public function new(pool:VertexPool, values:Array<Single>, generation:Int) {
		this.pool = pool;
		this.values = values;
		this.generation = generation;
	}
}

class ShapeDef {
	public var kind:ShapeKind;
	public var vertOffset:Int;
	public var vertCount:Int;
	public var depth:Single;
	public var radius:Single;
	public var localZ:Single;
	public var density:Single;

	var lease:VertexLease = null;

	public inline function new(kind:ShapeKind, vertOffset:Int = 0, vertCount:Int = 0, depth:Single = 0.0, radius:Single = 0.01, localZ:Single = 0.0,
			density:Single = 1.0) {
		this.kind = kind;
		this.vertOffset = vertOffset;
		this.vertCount = vertCount;
		this.depth = depth;
		this.radius = radius;
		this.localZ = localZ;
		this.density = density;
	}

	/** Repoints this descriptor at stored geometry, so one object can serve many shapes in turn. */
	public inline function assign(kind:ShapeKind, vertOffset:Int, vertCount:Int, depth:Single, radius:Single, localZ:Single, density:Single):Void {
		this.kind = kind;
		this.vertOffset = vertOffset;
		this.vertCount = vertCount;
		this.depth = depth;
		this.radius = radius;
		this.localZ = localZ;
		this.density = density;
		lease = null;
	}

	public inline function hasDepth():Bool {
		return depth > 0.0 || kind == Hull;
	}

	public function bindVertices(pool:VertexPool, values:Array<Single>):Void {
		lease = new VertexLease(pool, values, pool.generationAt(vertOffset));
	}

	public function ensureVertices(pool:VertexPool):Void {
		if (lease == null)
			return;
		if (lease.pool != pool)
			throw 'Shape vertex pool mismatch';
		if (pool.isLiveBlock(vertOffset, lease.generation))
			return;
		// Each reusable descriptor restores its geometry after its previous block is released.
		var offset = pool.allocateBlock(vertCount);
		for (i in 0...vertCount) {
			pool.vx[offset + i] = lease.values[i * 3];
			pool.vy[offset + i] = lease.values[i * 3 + 1];
			pool.vz[offset + i] = lease.values[i * 3 + 2];
		}
		vertOffset = offset;
		lease.generation = pool.generationAt(offset);
	}

	// Select the core vertex with the greatest dot product.
	public inline function getLocalSupport(pool:VertexPool, dir:Vec3):Vec3 {
		if (lease != null)
			ensureVertices(pool);
		var bestX:Single = 0.0;
		var bestY:Single = 0.0;
		var bestZ:Single = 0.0;

		if (kind != Point && vertCount > 0) {
			var idx0 = vertOffset;
			bestX = pool.vx[idx0];
			bestY = pool.vy[idx0];
			bestZ = pool.vz[idx0];
			var maxDot:Single = bestX * dir.x + bestY * dir.y + bestZ * dir.z;

			for (i in 1...vertCount) {
				var idx = vertOffset + i;
				var vx = pool.vx[idx];
				var vy = pool.vy[idx];
				var vz = pool.vz[idx];
				var d:Single = vx * dir.x + vy * dir.y + vz * dir.z;
				if (d > maxDot) {
					maxDot = d;
					bestX = vx;
					bestY = vy;
					bestZ = vz;
				}
			}
		}

		var halfDepth:Single = depth * 0.5;
		var zExtrude:Single = (depth > 0.0 && dir.z != 0.0) ? (dir.z > 0.0 ? halfDepth : -halfDepth) : 0.0;

		return new Vec3(bestX, bestY, bestZ + localZ + zExtrude);
	}
}
