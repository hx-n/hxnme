package hxn.me.physics.collision;

import hl.NativeArray;

class BroadPhase {
	public static inline var NULL_NODE:Int = -1;

	public var root:Int = NULL_NODE;
	public var nodeCount:Int = 0;
	public var nodeCapacity:Int;
	public var freeList:Int = 0;

	// Flat SoA Node Buffers
	public var aabb:NativeArray<Float>; // stride 6: minX, minY, minZ, maxX, maxY, maxZ
	public var parent:NativeArray<Int>;
	public var child1:NativeArray<Int>;
	public var child2:NativeArray<Int>;
	public var height:NativeArray<Int>;
	public var userData:NativeArray<Int>; // Stores ShapeId

	// Flat stack for allocation-free tree queries
	var queryStack:NativeArray<Int>;

	// Output pairs buffer: stride 2 (shapeA, shapeB)
	public var pairs:NativeArray<Int>;
	public var pairCount:Int = 0;
	public var maxPairs:Int;

	public function new(capacity:Int = 4096, maxPairs:Int = 16384) {
		this.nodeCapacity = capacity;
		this.maxPairs = maxPairs;

		aabb = new NativeArray<Float>(capacity * 6);
		parent = new NativeArray<Int>(capacity);
		child1 = new NativeArray<Int>(capacity);
		child2 = new NativeArray<Int>(capacity);
		height = new NativeArray<Int>(capacity);
		userData = new NativeArray<Int>(capacity);
		queryStack = new NativeArray<Int>(capacity);
		pairs = new NativeArray<Int>(Std.int(Math.min(maxPairs, 4096)) * 2);

		for (i in 0...capacity - 1) {
			parent[i] = i + 1;
			height[i] = -1;
		}
		parent[capacity - 1] = NULL_NODE;
		height[capacity - 1] = -1;
	}

	/**
	 * Room for `capacity` tree nodes, keeping the tree. The new nodes join the free list after the ones already on it, so nodes are
	 * handed out in the order a tree made that large from the start hands them out.
	 */
	public function growNodes(capacity:Int):Void {
		if (capacity <= nodeCapacity)
			return;
		var old = nodeCapacity;
		var wide = new NativeArray<Float>(capacity * 6);
		wide.blit(0, aabb, 0, old * 6);
		aabb = wide;
		parent = hxn.me.math.Grow.ints(parent, old, capacity);
		child1 = hxn.me.math.Grow.ints(child1, old, capacity);
		child2 = hxn.me.math.Grow.ints(child2, old, capacity);
		height = hxn.me.math.Grow.ints(height, old, capacity);
		userData = hxn.me.math.Grow.ints(userData, old, capacity);
		queryStack = hxn.me.math.Grow.ints(queryStack, old, capacity);
		nodeCapacity = capacity;
		linkFree(old);
	}

	/** Puts the nodes from `from` to the end on the free list, after the nodes already on it. */
	public function linkFree(from:Int):Void {
		var capacity = nodeCapacity;
		if (from >= capacity)
			return;
		for (i in from...capacity - 1) {
			parent[i] = i + 1;
			height[i] = -1;
		}
		parent[capacity - 1] = NULL_NODE;
		height[capacity - 1] = -1;
		if (freeList == NULL_NODE)
			freeList = from;
		else {
			var tail = freeList;
			while (parent[tail] != NULL_NODE)
				tail = parent[tail];
			parent[tail] = from;
		}
	}

	inline function allocateNode():Int {
		if (freeList == NULL_NODE)
			throw 'Broad-phase node capacity exceeded';
		var nodeId = freeList;
		freeList = parent[nodeId];
		parent[nodeId] = NULL_NODE;
		child1[nodeId] = NULL_NODE;
		child2[nodeId] = NULL_NODE;
		height[nodeId] = 0;
		userData[nodeId] = -1;
		nodeCount++;
		return nodeId;
	}

	public function createProxy(minX:Float, minY:Float, minZ:Float, maxX:Float, maxY:Float, maxZ:Float, shapeId:Int):Int {
		var proxyId = allocateNode();
		var b6 = proxyId * 6;
		var margin = 0.05; // Fattening margin for temporal coherence

		aabb[b6] = minX - margin;
		aabb[b6 + 1] = minY - margin;
		aabb[b6 + 2] = minZ - margin;
		aabb[b6 + 3] = maxX + margin;
		aabb[b6 + 4] = maxY + margin;
		aabb[b6 + 5] = maxZ + margin;
		userData[proxyId] = shapeId;
		height[proxyId] = 0;

		insertLeaf(proxyId);
		return proxyId;
	}

	public function updateProxy(proxyId:Int, minX:Float, minY:Float, minZ:Float, maxX:Float, maxY:Float, maxZ:Float, force:Bool = false):Void {
		var b6 = proxyId * 6;
		// Skip tree re-insertion if still inside fat AABB
		if (!force && aabb[b6] <= minX && aabb[b6 + 1] <= minY && aabb[b6 + 2] <= minZ && aabb[b6 + 3] >= maxX && aabb[b6 + 4] >= maxY && aabb[b6 + 5] >= maxZ) {
			return;
		}

		removeLeaf(proxyId);

		var margin = 0.05;
		aabb[b6] = minX - margin;
		aabb[b6 + 1] = minY - margin;
		aabb[b6 + 2] = minZ - margin;
		aabb[b6 + 3] = maxX + margin;
		aabb[b6 + 4] = maxY + margin;
		aabb[b6 + 5] = maxZ + margin;

		insertLeaf(proxyId);
	}

	public function destroyProxy(proxyId:Int):Void {
		if (proxyId < 0 || proxyId >= nodeCapacity || height[proxyId] != 0 || userData[proxyId] < 0)
			throw 'Invalid broad-phase proxy';
		removeLeaf(proxyId);
		userData[proxyId] = -1;
		freeNode(proxyId);
		pairCount = 0;
	}

	// Unified 2D/3D Surface Area Heuristic: reduces to 2*wx*wy when wz == 0
	inline function getPerimeter(nodeId:Int):Float {
		var b6 = nodeId * 6;
		var wx = aabb[b6 + 3] - aabb[b6];
		var wy = aabb[b6 + 4] - aabb[b6 + 1];
		var wz = aabb[b6 + 5] - aabb[b6 + 2];
		return 2.0 * (wx * wy + wy * wz + wz * wx);
	}

	inline function combineAABB(outNode:Int, nodeA:Int, nodeB:Int):Void {
		var o = outNode * 6;
		var a = nodeA * 6;
		var b = nodeB * 6;
		aabb[o] = aabb[a] < aabb[b] ? aabb[a] : aabb[b];
		aabb[o + 1] = aabb[a + 1] < aabb[b + 1] ? aabb[a + 1] : aabb[b + 1];
		aabb[o + 2] = aabb[a + 2] < aabb[b + 2] ? aabb[a + 2] : aabb[b + 2];
		aabb[o + 3] = aabb[a + 3] > aabb[b + 3] ? aabb[a + 3] : aabb[b + 3];
		aabb[o + 4] = aabb[a + 4] > aabb[b + 4] ? aabb[a + 4] : aabb[b + 4];
		aabb[o + 5] = aabb[a + 5] > aabb[b + 5] ? aabb[a + 5] : aabb[b + 5];
	}

	public inline function testOverlap(nodeA:Int, nodeB:Int):Bool {
		var a = nodeA * 6;
		var b = nodeB * 6;
		return (aabb[a] <= aabb[b + 3] && aabb[a + 3] >= aabb[b])
			&& (aabb[a + 1] <= aabb[b + 4] && aabb[a + 4] >= aabb[b + 1])
			&& (aabb[a + 2] <= aabb[b + 5] && aabb[a + 5] >= aabb[b + 2]);
	}

	public static inline function filtersAllow(a:Int, b:Int, categoryBits:NativeArray<Int>, maskBits:NativeArray<Int>, groupIndex:NativeArray<Int>):Bool {
		var group = groupIndex[a];
		return group != 0
			&& group == groupIndex[b] ? group > 0 : (categoryBits[a] & maskBits[b]) != 0 && (categoryBits[b] & maskBits[a]) != 0;
	}

	/** Writes the shapes whose boxes overlap proxy `proxy`'s box into `out`, including its own; returns the count. */
	public function overlapping(proxy:Int, out:hl.NativeArray<Int>):Int {
		if (root == NULL_NODE)
			return 0;
		var count = 0;
		var sp = 0;
		queryStack[sp++] = root;
		while (sp > 0) {
			var node = queryStack[--sp];
			if (!testOverlap(proxy, node))
				continue;
			if (child1[node] == NULL_NODE) {
				out[count++] = userData[node];
			} else {
				if (sp + 2 > nodeCapacity)
					throw 'Broad-phase query stack capacity exceeded';
				queryStack[sp++] = child1[node];
				queryStack[sp++] = child2[node];
			}
		}
		return count;
	}

	/** Writes the shapes whose boxes overlap the given box into `out`; returns the count. */
	public function overlappingBox(minX:Float, minY:Float, minZ:Float, maxX:Float, maxY:Float, maxZ:Float, out:hl.NativeArray<Int>):Int {
		if (root == NULL_NODE)
			return 0;
		var count = 0;
		var sp = 0;
		queryStack[sp++] = root;
		while (sp > 0) {
			var node = queryStack[--sp];
			var o = node * 6;
			if (aabb[o] > maxX || aabb[o + 1] > maxY || aabb[o + 2] > maxZ || aabb[o + 3] < minX || aabb[o + 4] < minY || aabb[o + 5] < minZ)
				continue;
			if (child1[node] == NULL_NODE) {
				out[count++] = userData[node];
			} else {
				if (sp + 2 > nodeCapacity)
					throw 'Broad-phase query stack capacity exceeded';
				queryStack[sp++] = child1[node];
				queryStack[sp++] = child2[node];
			}
		}
		return count;
	}

	public function queryAABB(minX:Float, minY:Float, minZ:Float, maxX:Float, maxY:Float, maxZ:Float, visit:Int->Bool):Void {
		if (root == NULL_NODE)
			return;
		var sp = 0;
		queryStack[sp++] = root;
		while (sp > 0) {
			var node = queryStack[--sp];
			var o = node * 6;
			if (aabb[o] > maxX || aabb[o + 1] > maxY || aabb[o + 2] > maxZ || aabb[o + 3] < minX || aabb[o + 4] < minY || aabb[o + 5] < minZ)
				continue;
			if (child1[node] == NULL_NODE) {
				if (!visit(userData[node]))
					return;
			} else {
				// A binary tree with nodeCapacity nodes needs at most nodeCapacity stack slots.
				if (sp + 2 > nodeCapacity)
					throw 'Broad-phase query stack capacity exceeded';
				queryStack[sp++] = child1[node];
				queryStack[sp++] = child2[node];
			}
		}
	}

	function insertLeaf(leaf:Int):Void {
		if (root == NULL_NODE) {
			root = leaf;
			parent[root] = NULL_NODE;
			return;
		}

		var l6 = leaf * 6;
		var lx0 = aabb[l6];
		var ly0 = aabb[l6 + 1];
		var lz0 = aabb[l6 + 2];
		var lx1 = aabb[l6 + 3];
		var ly1 = aabb[l6 + 4];
		var lz1 = aabb[l6 + 5];

		var index = root;
		while (child1[index] != NULL_NODE) {
			var c1 = child1[index];
			var c2 = child2[index];
			var area = getPerimeter(index);

			var i6 = index * 6;
			var ux0 = lx0 < aabb[i6] ? lx0 : aabb[i6];
			var uy0 = ly0 < aabb[i6 + 1] ? ly0 : aabb[i6 + 1];
			var uz0 = lz0 < aabb[i6 + 2] ? lz0 : aabb[i6 + 2];
			var ux1 = lx1 > aabb[i6 + 3] ? lx1 : aabb[i6 + 3];
			var uy1 = ly1 > aabb[i6 + 4] ? ly1 : aabb[i6 + 4];
			var uz1 = lz1 > aabb[i6 + 5] ? lz1 : aabb[i6 + 5];
			var uwx = ux1 - ux0;
			var uwy = uy1 - uy0;
			var uwz = uz1 - uz0;
			var combinedArea = 2.0 * (uwx * uwy + uwy * uwz + uwz * uwx);

			var cost = 2.0 * combinedArea;
			var inheritanceCost = 2.0 * (combinedArea - area);

			// Cost of descending into child1
			var c1_6 = c1 * 6;
			var c1x0 = lx0 < aabb[c1_6] ? lx0 : aabb[c1_6];
			var c1y0 = ly0 < aabb[c1_6 + 1] ? ly0 : aabb[c1_6 + 1];
			var c1z0 = lz0 < aabb[c1_6 + 2] ? lz0 : aabb[c1_6 + 2];
			var c1x1 = lx1 > aabb[c1_6 + 3] ? lx1 : aabb[c1_6 + 3];
			var c1y1 = ly1 > aabb[c1_6 + 4] ? ly1 : aabb[c1_6 + 4];
			var c1z1 = lz1 > aabb[c1_6 + 5] ? lz1 : aabb[c1_6 + 5];
			var c1wx = c1x1 - c1x0;
			var c1wy = c1y1 - c1y0;
			var c1wz = c1z1 - c1z0;
			var c1Area = 2.0 * (c1wx * c1wy + c1wy * c1wz + c1wz * c1wx);
			var cost1 = (child1[c1] == NULL_NODE ? c1Area : c1Area - getPerimeter(c1)) + inheritanceCost;

			// Cost of descending into child2
			var c2_6 = c2 * 6;
			var c2x0 = lx0 < aabb[c2_6] ? lx0 : aabb[c2_6];
			var c2y0 = ly0 < aabb[c2_6 + 1] ? ly0 : aabb[c2_6 + 1];
			var c2z0 = lz0 < aabb[c2_6 + 2] ? lz0 : aabb[c2_6 + 2];
			var c2x1 = lx1 > aabb[c2_6 + 3] ? lx1 : aabb[c2_6 + 3];
			var c2y1 = ly1 > aabb[c2_6 + 4] ? ly1 : aabb[c2_6 + 4];
			var c2z1 = lz1 > aabb[c2_6 + 5] ? lz1 : aabb[c2_6 + 5];
			var c2wx = c2x1 - c2x0;
			var c2wy = c2y1 - c2y0;
			var c2wz = c2z1 - c2z0;
			var c2Area = 2.0 * (c2wx * c2wy + c2wy * c2wz + c2wz * c2wx);
			var cost2 = (child1[c2] == NULL_NODE ? c2Area : c2Area - getPerimeter(c2)) + inheritanceCost;

			if (cost < cost1 && cost < cost2)
				break;
			index = cost1 < cost2 ? c1 : c2;
		}

		var sibling = index;
		var oldParent = parent[sibling];
		var newParent = allocateNode();
		parent[newParent] = oldParent;
		combineAABB(newParent, leaf, sibling);
		height[newParent] = height[sibling] + 1;

		if (oldParent != NULL_NODE) {
			if (child1[oldParent] == sibling)
				child1[oldParent] = newParent;
			else
				child2[oldParent] = newParent;
		} else {
			root = newParent;
		}

		child1[newParent] = sibling;
		child2[newParent] = leaf;
		parent[sibling] = newParent;
		parent[leaf] = newParent;

		fixUpwards(newParent);
	}

	function removeLeaf(leaf:Int):Void {
		if (leaf == root) {
			root = NULL_NODE;
			return;
		}
		var p = parent[leaf];
		var grandParent = parent[p];
		var sibling = child1[p] == leaf ? child2[p] : child1[p];

		if (grandParent != NULL_NODE) {
			if (child1[grandParent] == p)
				child1[grandParent] = sibling;
			else
				child2[grandParent] = sibling;
			parent[sibling] = grandParent;
			freeNode(p);
			fixUpwards(grandParent);
		} else {
			root = sibling;
			parent[sibling] = NULL_NODE;
			freeNode(p);
		}
	}

	inline function freeNode(nodeId:Int):Void {
		parent[nodeId] = freeList;
		height[nodeId] = -1;
		freeList = nodeId;
		nodeCount--;
	}

	// Rotate an imbalanced subtree and return its new root.
	function balance(a:Int):Int {
		if (child1[a] == NULL_NODE)
			return a;
		var b = child1[a], c = child2[a];
		var difference = height[c] - height[b];
		if (difference > 1) {
			var f = child1[c], g = child2[c];
			var oldParent = parent[a];
			child1[c] = a;
			parent[c] = oldParent;
			parent[a] = c;
			if (oldParent == NULL_NODE)
				root = c;
			else if (child1[oldParent] == a)
				child1[oldParent] = c;
			else
				child2[oldParent] = c;
			if (height[f] > height[g]) {
				child2[c] = f;
				child2[a] = g;
				parent[g] = a;
			} else {
				child2[c] = g;
				child2[a] = f;
				parent[f] = a;
			}
			var a2 = child2[a], c2 = child2[c];
			combineAABB(a, b, a2);
			height[a] = 1 + (height[b] > height[a2] ? height[b] : height[a2]);
			combineAABB(c, a, c2);
			height[c] = 1 + (height[a] > height[c2] ? height[a] : height[c2]);
			return c;
		}
		if (difference < -1) {
			var d = child1[b], e = child2[b];
			var oldParent = parent[a];
			child1[b] = a;
			parent[b] = oldParent;
			parent[a] = b;
			if (oldParent == NULL_NODE)
				root = b;
			else if (child1[oldParent] == a)
				child1[oldParent] = b;
			else
				child2[oldParent] = b;
			if (height[d] > height[e]) {
				child2[b] = d;
				child1[a] = e;
				parent[e] = a;
			} else {
				child2[b] = e;
				child1[a] = d;
				parent[d] = a;
			}
			var a1 = child1[a], b2 = child2[b];
			combineAABB(a, a1, c);
			height[a] = 1 + (height[a1] > height[c] ? height[a1] : height[c]);
			combineAABB(b, a, b2);
			height[b] = 1 + (height[a] > height[b2] ? height[a] : height[b2]);
			return b;
		}
		return a;
	}

	function fixUpwards(index:Int):Void {
		while (index != NULL_NODE) {
			index = balance(index);
			var c1 = child1[index];
			var c2 = child2[index];
			var h1 = height[c1];
			var h2 = height[c2];
			height[index] = 1 + (h1 > h2 ? h1 : h2);
			combineAABB(index, c1, c2);
			index = parent[index];
		}
	}

	// Finds all overlapping shape pairs in the shared 2D/3D world
	public function findPairs(shapeCount:Int, shapeProxy:NativeArray<Int>, shapeBody:NativeArray<Int>, bodyType:NativeArray<Int>,
			categoryBits:NativeArray<Int>, maskBits:NativeArray<Int>, groupIndex:NativeArray<Int>, isAwake:NativeArray<Int> = null,
			activeIds:NativeArray<Int> = null):Void {
		pairCount = 0;
		if (root == NULL_NODE)
			return;

		for (position in 0...shapeCount) {
			var sA = activeIds == null ? position : activeIds[position];
			var proxyA = shapeProxy[sA];
			if (proxyA == NULL_NODE)
				continue;
			var bodyA = shapeBody[sA];
			var dynamicA = bodyType[bodyA] == 2;
			var passiveA = bodyType[bodyA] == 0 || (isAwake != null && dynamicA && isAwake[bodyA] == 0);

			var sp = 0;
			queryStack[sp++] = root;

			while (sp > 0) {
				var nodeId = queryStack[--sp];
				if (nodeId == NULL_NODE)
					continue;

				if (testOverlap(proxyA, nodeId)) {
					if (child1[nodeId] == NULL_NODE) {
						var sB = userData[nodeId];
						// Avoid duplicate pairs (sA < sB) and self-body collisions. A pair with no dynamic
						// body gives the solver nothing to move, so static and kinematic shapes never pair.
						if (sA < sB) {
							var bodyB = shapeBody[sB];
							var allowed = filtersAllow(sA, sB, categoryBits, maskBits, groupIndex);
							var passiveB = bodyType[bodyB] == 0 || (isAwake != null && bodyType[bodyB] == 2 && isAwake[bodyB] == 0);
							if (allowed && bodyA != bodyB && (dynamicA || bodyType[bodyB] == 2) && !(passiveA && passiveB)) {
								if (pairCount < maxPairs) {
									if (pairCount * 2 == pairs.length)
										growPairs();
									var p2 = pairCount * 2;
									pairs[p2] = sA;
									pairs[p2 + 1] = sB;
									pairCount++;
								}
							}
						}
					} else {
						queryStack[sp++] = child1[nodeId];
						queryStack[sp++] = child2[nodeId];
					}
				}
			}
		}
	}

	/** Doubles the pair storage toward `maxPairs`, keeping the pairs found so far. */
	function growPairs():Void {
		var bigger = new NativeArray<Int>(Std.int(Math.min(maxPairs * 2.0, pairs.length * 2.0)));
		bigger.blit(0, pairs, 0, pairCount * 2);
		pairs = bigger;
	}

	/** Visits the whole tree, free nodes included, for `WorldSnapshot`. */
	@:noCompletion public function visitState(s:hxn.me.physics.core.WorldSnapshot):Void {
		root = s.int(root);
		nodeCount = s.int(nodeCount);
		freeList = s.int(freeList);
		s.doubles(aabb, nodeCapacity * 6);
		s.ints(parent, nodeCapacity);
		s.ints(child1, nodeCapacity);
		s.ints(child2, nodeCapacity);
		s.ints(height, nodeCapacity);
		s.ints(userData, nodeCapacity);
	}
}
