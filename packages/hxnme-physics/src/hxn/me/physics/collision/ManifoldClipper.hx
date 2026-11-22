package hxn.me.physics.collision;

import hxn.me.physics.geom.ConvexHull;
import hxn.me.physics.geom.ShapeDef;
import hxn.me.physics.geom.ShapeDef.ShapeKind;
import hxn.me.physics.geom.VertexPool;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;

class ClippedContact {
	public var point:Vec3;
	public var penetration:Float;
	public var feature:Int;

	public function new(point:Vec3, penetration:Float, feature:Int) {
		this.point = point;
		this.penetration = penetration;
		this.feature = feature;
	}
}

private class ClipVertex {
	public var point:Vec3;
	public var id:Int;

	public function new(point:Vec3, id:Int) {
		this.point = point;
		this.id = id;
	}
}

private class ClipFace {
	public var vertices:Array<Vec3>;
	public var normal:Vec3;
	public var id:Int;

	public function new(vertices:Array<Vec3>, normal:Vec3, id:Int) {
		this.vertices = vertices;
		this.normal = normal;
		this.id = id;
	}
}

private class LocalFace {
	public var indices:Array<Int>;
	public var normal:Vec3;
	public var id:Int;

	public function new(indices:Array<Int>, normal:Vec3, id:Int) {
		this.indices = indices;
		this.normal = normal;
		this.id = id;
	}
}

class ClipTopology {
	public var points:Array<Vec3>;
	public var faces:Array<LocalFace>;

	/** Polygon winding the faces were built for; a reshape that keeps it can update in place. */
	public var ccw:Bool = true;

	public function new(points:Array<Vec3>, faces:Array<LocalFace>) {
		this.points = points;
		this.faces = faces;
	}
}

/** Clipped contacts remain valid until the next generate call using this workspace. */
class ClipWorkspace {
	var pointPool:Array<Vec3> = [];
	var facePool:Array<ClipFace> = [];
	var vertexPool:Array<ClipVertex> = [];
	var contactPool:Array<ClippedContact> = [];
	var pointCount:Int = 0;
	var faceCount:Int = 0;
	var vertexCount:Int = 0;
	var contactCount:Int = 0;

	public var transformedA:Array<Vec3> = [];
	public var transformedB:Array<Vec3> = [];
	public var facesA:Array<ClipFace> = [];
	public var facesB:Array<ClipFace> = [];
	public var clipA:Array<ClipVertex> = [];
	public var clipB:Array<ClipVertex> = [];
	public var contacts:Array<ClippedContact> = [];
	// Inward normal of the side plane currently clipping the incident face.
	public var plane:Vec3 = new Vec3();

	public function new() {}

	public function reset():Void {
		pointCount = faceCount = vertexCount = contactCount = 0;
		transformedA.resize(0);
		transformedB.resize(0);
		facesA.resize(0);
		facesB.resize(0);
		clipA.resize(0);
		clipB.resize(0);
		contacts.resize(0);
	}

	public function point(x:Float, y:Float, z:Float):Vec3 {
		if (pointCount == pointPool.length)
			pointPool.push(new Vec3());
		var result = pointPool[pointCount++];
		result.x = x;
		result.y = y;
		result.z = z;
		return result;
	}

	public function face(id:Int):ClipFace {
		if (faceCount == facePool.length)
			facePool.push(new ClipFace([], new Vec3(), 0));
		var result = facePool[faceCount++];
		result.vertices.resize(0);
		result.id = id;
		return result;
	}

	public function vertex(point:Vec3, id:Int):ClipVertex {
		if (vertexCount == vertexPool.length)
			vertexPool.push(new ClipVertex(point, id));
		var result = vertexPool[vertexCount++];
		result.point = point;
		result.id = id;
		return result;
	}

	public function contact(point:Vec3, penetration:Float, feature:Int):ClippedContact {
		if (contactCount == contactPool.length)
			contactPool.push(new ClippedContact(point, penetration, feature));
		var result = contactPool[contactCount++];
		result.point = point;
		result.penetration = penetration;
		result.feature = feature;
		return result;
	}
}

/** Clips the incident face to the reference face's side planes. */
class ManifoldClipper {
	static function localVertices(pool:VertexPool, def:ShapeDef):Array<Vec3> {
		var points:Array<Vec3> = [];
		for (i in 0...def.vertCount) {
			var k = def.vertOffset + i;
			points.push(new Vec3(pool.vx[k], pool.vy[k], pool.vz[k] + def.localZ));
		}
		return points;
	}

	static function addLocalFace(faces:Array<LocalFace>, points:Array<Vec3>, indices:Array<Int>, id:Int):Void {
		if (indices.length < 2)
			return;
		var normal:Vec3;
		if (indices.length == 2) {
			var edge = Vec3.sub(points[indices[1]], points[indices[0]]);
			normal = Vec3.normalize(new Vec3(edge.y, -edge.x, 0));
		} else
			normal = Vec3.normalize(Vec3.cross(Vec3.sub(points[indices[1]], points[indices[0]]), Vec3.sub(points[indices[2]], points[indices[0]])));
		faces.push(new LocalFace(indices, normal, id));
	}

	public static function buildTopology(pool:VertexPool, def:ShapeDef):ClipTopology {
		var result:Array<LocalFace> = [];
		var local = localVertices(pool, def);
		if (def.kind == Polygon) {
			var points:Array<Vec3> = [];
			if (def.depth > 0) {
				for (p in local)
					points.push(new Vec3(p.x, p.y, p.z - def.depth * 0.5));
				for (p in local)
					points.push(new Vec3(p.x, p.y, p.z + def.depth * 0.5));
			} else
				points = local;
			var n = def.vertCount;
			var sign = 0.0;
			for (i in 0...n) {
				var a = local[i], b = local[(i + 1) % n];
				sign += a.x * b.y - a.y * b.x;
			}
			var ccw = sign > 0;
			for (i in 0...n) {
				var j = (i + 1) % n;
				if (def.depth > 0) {
					if (ccw)
						addLocalFace(result, points, [i, j, j + n, i + n], i);
					else
						addLocalFace(result, points, [j, i, i + n, j + n], i);
				} else {
					if (ccw)
						addLocalFace(result, points, [i, j], i);
					else
						addLocalFace(result, points, [j, i], i);
				}
			}
			if (def.depth > 0) {
				var bottom:Array<Int> = [], top:Array<Int> = [];
				for (i in 0...n) {
					if (ccw) {
						bottom.unshift(i);
						top.push(i + n);
					} else {
						bottom.push(i);
						top.unshift(i + n);
					}
				}
				addLocalFace(result, points, bottom, n);
				addLocalFace(result, points, top, n + 1);
			}
			var topology = new ClipTopology(points, result);
			topology.ccw = ccw;
			return topology;
		} else if (def.kind == Hull) {
			var triangles = ConvexHull.triangles(local);
			var points = local;
			for (t in 0...Std.int(triangles.length / 3)) {
				var ia = triangles[t * 3],
					ib = triangles[t * 3 + 1],
					ic = triangles[t * 3 + 2];
				var a = points[ia];
				var normal = Vec3.normalize(Vec3.cross(Vec3.sub(points[ib], a), Vec3.sub(points[ic], a)));
				var distance = Vec3.dot(normal, a);
				var seen = false;
				for (f in result)
					if (Vec3.dot(f.normal, normal) > 1 - 1e-5 && Math.abs(Vec3.dot(f.normal, points[f.indices[0]]) - distance) < 1e-4) {
						seen = true;
						break;
					}
				if (seen)
					continue;
				var coplanar:Array<Int> = [];
				for (u in 0...Std.int(triangles.length / 3)) {
					var u0 = triangles[u * 3],
						u1 = triangles[u * 3 + 1],
						u2 = triangles[u * 3 + 2];
					var un = Vec3.normalize(Vec3.cross(Vec3.sub(points[u1], points[u0]), Vec3.sub(points[u2], points[u0])));
					if (Vec3.dot(normal, un) < 1 - 1e-5 || Math.abs(Vec3.dot(normal, points[u0]) - distance) >= 1e-4)
						continue;
					for (index in [u0, u1, u2])
						if (coplanar.indexOf(index) < 0)
							coplanar.push(index);
				}
				var center = new Vec3();
				for (i in coplanar)
					center = Vec3.add(center, points[i]);
				center = Vec3.scale(center, 1.0 / coplanar.length);
				var axis = Vec3.normalize(Vec3.sub(points[coplanar[0]], center));
				var other = Vec3.cross(normal, axis);
				coplanar.sort((i, j) -> {
					var di = Vec3.sub(points[i], center),
						dj = Vec3.sub(points[j], center);
					var ai = Math.atan2(Vec3.dot(di, other), Vec3.dot(di, axis));
					var aj = Math.atan2(Vec3.dot(dj, other), Vec3.dot(dj, axis));
					return ai < aj ? -1 : (ai > aj ? 1 : 0);
				});
				addLocalFace(result, points, coplanar, t);
			}
			return new ClipTopology(points, result);
		}
		return new ClipTopology(local, result);
	}

	/**
	 * Moves a polygon topology's points and face normals to the shape's
	 * current vertices without allocating. Returns false, leaving the topology
	 * untouched, when the winding or vertex layout changed and it must be
	 * rebuilt instead.
	 */
	public static function refreshPolygon(pool:VertexPool, def:ShapeDef, topology:ClipTopology):Bool {
		if (topology == null || def.kind != Polygon)
			return false;
		var n = def.vertCount;
		var points = topology.points;
		if (points.length != (def.depth > 0 ? 2 * n : n))
			return false;
		var sign = 0.0;
		for (i in 0...n) {
			var a = def.vertOffset + i, b = def.vertOffset + (i + 1) % n;
			sign += pool.vx[a] * pool.vy[b] - pool.vy[a] * pool.vx[b];
		}
		if ((sign > 0) != topology.ccw)
			return false;
		var half = def.depth * 0.5;
		for (i in 0...n) {
			var k = def.vertOffset + i;
			var z = pool.vz[k] + def.localZ;
			var p = points[i];
			p.x = pool.vx[k];
			p.y = pool.vy[k];
			p.z = def.depth > 0 ? z - half : z;
			if (def.depth > 0) {
				var q = points[i + n];
				q.x = pool.vx[k];
				q.y = pool.vy[k];
				q.z = z + half;
			}
		}
		for (face in topology.faces) {
			var indices = face.indices;
			var a = points[indices[0]], b = points[indices[1]];
			if (indices.length == 2)
				setUnit(face.normal, b.y - a.y, a.x - b.x, 0.0);
			else {
				var c = points[indices[2]];
				var ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z;
				var vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z;
				setUnit(face.normal, uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx);
			}
		}
		return true;
	}

	static inline function setUnit(out:Vec3, x:Float, y:Float, z:Float):Void {
		var lengthSq = x * x + y * y + z * z;
		if (lengthSq < 1e-12) {
			out.x = 0.0;
			out.y = 1.0;
			out.z = 0.0;
			return;
		}
		var inv = 1.0 / Math.sqrt(lengthSq);
		out.x = x * inv;
		out.y = y * inv;
		out.z = z * inv;
	}

	static inline function rotateInto(out:Vec3, p:Vec3, rot:Quat, x:Float, y:Float, z:Float):Void {
		var tx:Float = 2.0 * (rot.y * p.z - rot.z * p.y);
		var ty:Float = 2.0 * (rot.z * p.x - rot.x * p.z);
		var tz:Float = 2.0 * (rot.x * p.y - rot.y * p.x);
		out.x = x + p.x + rot.w * tx + (rot.y * tz - rot.z * ty);
		out.y = y + p.y + rot.w * ty + (rot.z * tx - rot.x * tz);
		out.z = z + p.z + rot.w * tz + (rot.x * ty - rot.y * tx);
	}

	static function faces(topology:ClipTopology, pos:Vec3, rot:Quat, workspace:ClipWorkspace, points:Array<Vec3>, result:Array<ClipFace>):Array<ClipFace> {
		for (p in topology.points) {
			var transformed = workspace.point(0, 0, 0);
			rotateInto(transformed, p, rot, pos.x, pos.y, pos.z);
			points.push(transformed);
		}
		for (face in topology.faces) {
			var transformedFace = workspace.face(face.id);
			for (index in face.indices)
				transformedFace.vertices.push(points[index]);
			var normal = transformedFace.normal;
			if (face.indices.length == 2) {
				var a = transformedFace.vertices[0],
					b = transformedFace.vertices[1];
				var nx = b.y - a.y, ny = a.x - b.x;
				var length = Math.sqrt(nx * nx + ny * ny);
				if (length < 1e-6) {
					normal.x = 0;
					normal.y = 1;
					normal.z = 0;
				} else {
					normal.x = nx / length;
					normal.y = ny / length;
					normal.z = 0;
				}
			} else {
				rotateInto(normal, face.normal, rot, 0, 0, 0);
				var length = Math.sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
				if (length < 1e-6) {
					normal.x = 0;
					normal.y = 1;
					normal.z = 0;
				} else {
					// HashLink computes `s /= f` on a Single in single precision.
					// The cast keeps the division in Float, as on hxcpp.
					normal.x = (normal.x : Float) / length;
					normal.y = (normal.y : Float) / length;
					normal.z = (normal.z : Float) / length;
				}
			}
			result.push(transformedFace);
		}
		return result;
	}

	static function clip(vertices:Array<ClipVertex>, inward:Vec3, planePoint:Vec3, planeId:Int, workspace:ClipWorkspace,
			result:Array<ClipVertex>):Array<ClipVertex> {
		result.resize(0);
		if (vertices.length == 0)
			return result;
		var prev = vertices[vertices.length - 1];
		var prevSide = inward.x * (prev.point.x - planePoint.x) + inward.y * (prev.point.y - planePoint.y) + inward.z * (prev.point.z - planePoint.z);
		for (current in vertices) {
			var side = inward.x * (current.point.x - planePoint.x) + inward.y * (current.point.y - planePoint.y) + inward.z * (current.point.z - planePoint.z);
			if ((side >= -1e-5) != (prevSide >= -1e-5)) {
				var t = prevSide / (prevSide - side);
				var point = workspace.point(prev.point.x
					+ (current.point.x - prev.point.x) * t, prev.point.y
					+ (current.point.y - prev.point.y) * t,
					prev.point.z
					+ (current.point.z - prev.point.z) * t);
				result.push(workspace.vertex(point, 256 + planeId * 32 + ((prev.id < current.id ? prev.id : current.id) & 31)));
			}
			if (side >= -1e-5)
				result.push(current);
			prev = current;
			prevSide = side;
		}
		return result;
	}

	public static function generate(pool:VertexPool, a:ShapeDef, posA:Vec3, rotA:Quat, b:ShapeDef, posB:Vec3, rotB:Quat, normal:Vec3,
			topologyA:ClipTopology = null, topologyB:ClipTopology = null, workspace:ClipWorkspace = null):Array<ClippedContact> {
		if (workspace == null)
			workspace = new ClipWorkspace();
		workspace.reset();
		if ((a.kind != Polygon && a.kind != Hull) || (b.kind != Polygon && b.kind != Hull) || a.hasDepth() != b.hasDepth())
			return workspace.contacts;
		if (!a.hasDepth() && Math.abs(normal.z) > 0.1)
			return workspace.contacts;
		var af = faces(topologyA == null ? buildTopology(pool, a) : topologyA, posA, rotA, workspace, workspace.transformedA, workspace.facesA);
		var bf = faces(topologyB == null ? buildTopology(pool, b) : topologyB, posB, rotB, workspace, workspace.transformedB, workspace.facesB);
		if (af.length == 0 || bf.length == 0)
			return workspace.contacts;
		var aBest = af[0], bBest = bf[0];
		var aDot = -Math.POSITIVE_INFINITY, bDot = -Math.POSITIVE_INFINITY;
		for (f in af) {
			var d = Vec3.dot(f.normal, normal);
			if (d > aDot) {
				aDot = d;
				aBest = f;
			}
		}
		for (f in bf) {
			var d = -Vec3.dot(f.normal, normal);
			if (d > bDot) {
				bDot = d;
				bBest = f;
			}
		}
		var referenceOnA = aDot >= bDot;
		var reference = referenceOnA ? aBest : bBest;
		var incidentFaces = referenceOnA ? bf : af;
		var incident = incidentFaces[0];
		var minDot = Math.POSITIVE_INFINITY;
		for (f in incidentFaces) {
			var d = Vec3.dot(f.normal, reference.normal);
			if (d < minDot) {
				minDot = d;
				incident = f;
			}
		}
		var vertices = workspace.clipA;
		for (i in 0...incident.vertices.length)
			vertices.push(workspace.vertex(incident.vertices[i], i));
		var plane = workspace.plane;
		var refs = reference.vertices;
		var count = refs.length;
		if (count == 2) {
			var tx = refs[1].x - refs[0].x,
				ty = refs[1].y - refs[0].y,
				tz = refs[1].z - refs[0].z;
			setUnit(plane, tx, ty, tz);
			vertices = clip(vertices, plane, refs[0], 0, workspace, workspace.clipB);
			plane.x = -plane.x;
			plane.y = -plane.y;
			plane.z = -plane.z;
			vertices = clip(vertices, plane, refs[1], 1, workspace, workspace.clipA);
		} else {
			var n = reference.normal;
			for (i in 0...count) {
				var p = refs[i], q = refs[(i + 1) % count];
				var ex = q.x - p.x, ey = q.y - p.y, ez = q.z - p.z;
				setUnit(plane, n.y * ez - n.z * ey, n.z * ex - n.x * ez, n.x * ey - n.y * ex);
				vertices = clip(vertices, plane, p, i, workspace, vertices == workspace.clipA ? workspace.clipB : workspace.clipA);
			}
		}
		var contacts = workspace.contacts;
		var radius = a.radius + b.radius;
		var minEdgeSq = Math.POSITIVE_INFINITY;
		for (i in 0...count) {
			var p = refs[i], q = refs[(i + 1) % count];
			var ex = q.x - p.x, ey = q.y - p.y, ez = q.z - p.z;
			minEdgeSq = Math.min(minEdgeSq, ex * ex + ey * ey + ez * ez);
		}
		var cornerToleranceSq = Math.min(0.0025, minEdgeSq * 0.01);
		var nx:Float = reference.normal.x,
			ny:Float = reference.normal.y,
			nz:Float = reference.normal.z;
		var origin = refs[0];
		for (v in vertices) {
			var vp = v.point;
			var separation = nx * (vp.x - origin.x) + ny * (vp.y - origin.y) + nz * (vp.z - origin.z);
			var depth = radius - separation;
			if (depth <= 0)
				continue;
			var px = vp.x - nx * 0.5 * separation,
				py = vp.y - ny * 0.5 * separation,
				pz = vp.z - nz * 0.5 * separation;
			var localId = v.id;
			for (i in 0...count) {
				var r = refs[i];
				var dx = vp.x - r.x, dy = vp.y - r.y, dz = vp.z - r.z;
				var normalDistance = dx * nx + dy * ny + dz * nz;
				var tangentDistanceSq = dx * dx + dy * dy + dz * dz - normalDistance * normalDistance;
				if (tangentDistanceSq <= cornerToleranceSq) {
					localId = 2048 + i;
					break;
				}
			}
			var feature = (referenceOnA ? 0 : 1 << 28) | ((reference.id & 255) << 20) | ((incident.id & 255) << 12) | (localId & 4095);
			var duplicate = false;
			for (c in contacts) {
				var cx = c.point.x - px,
					cy = c.point.y - py,
					cz = c.point.z - pz;
				if (cx * cx + cy * cy + cz * cz < 1e-8)
					duplicate = true;
			}
			if (!duplicate)
				contacts.push(workspace.contact(workspace.point(px, py, pz), depth, feature));
		}
		var limit = a.hasDepth() ? 4 : 2;
		if (contacts.length > limit) {
			// Keep the deepest points; the sort is stable, so equal depths keep clipping order.
			for (i in 1...contacts.length) {
				var c = contacts[i];
				var j = i - 1;
				while (j >= 0 && contacts[j].penetration < c.penetration) {
					contacts[j + 1] = contacts[j];
					j--;
				}
				contacts[j + 1] = c;
			}
			contacts.resize(limit);
		}
		return contacts;
	}
}
