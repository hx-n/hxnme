package hxn.me.physics.geom;

/** Contiguous SoA vertex storage shared by shape descriptors. */
import hxn.me.math.Grow;
import hxn.me.math.Vec3;
import hxn.me.math.Simd.FloatBuffer;
import hl.NativeArray;

class VertexPool {
	public var vx:FloatBuffer;
	public var vy:FloatBuffer;
	public var vz:FloatBuffer;
	public var count:Int = 0; // High-water mark; released builder blocks stay below it.
	public var capacity:Int;

	var blockOrder:NativeArray<Int>;
	var blockActive:NativeArray<Int>;
	var blockRefs:NativeArray<Int>;
	var blockGeneration:NativeArray<Int>;
	var nextFree:NativeArray<Int>;
	var freeHead:Array<Int>;

	public function new(maxVerts:Int = 16384) {
		var cap = (maxVerts + 3) & ~3;
		capacity = cap;
		vx = new FloatBuffer(cap);
		vy = new FloatBuffer(cap);
		vz = new FloatBuffer(cap);
		blockOrder = new NativeArray<Int>(cap);
		blockActive = new NativeArray<Int>(cap);
		blockRefs = new NativeArray<Int>(cap);
		blockGeneration = new NativeArray<Int>(cap);
		nextFree = new NativeArray<Int>(cap);
		for (i in 0...cap)
			blockOrder[i] = -1;
		freeHead = [];
		for (i in 0...31)
			freeHead.push(-1);
	}

	/** Room for `cap` vertices, keeping every block where it is, so shapes' offsets stay valid. */
	public function grow(cap:Int):Void {
		cap = (cap + 3) & ~3;
		if (cap <= capacity)
			return;
		vx = Grow.floats(vx, capacity, cap);
		vy = Grow.floats(vy, capacity, cap);
		vz = Grow.floats(vz, capacity, cap);
		blockOrder = Grow.ints(blockOrder, capacity, cap, -1);
		blockActive = Grow.ints(blockActive, capacity, cap);
		blockRefs = Grow.ints(blockRefs, capacity, cap);
		blockGeneration = Grow.ints(blockGeneration, capacity, cap);
		nextFree = Grow.ints(nextFree, capacity, cap);
		capacity = cap;
	}

	public function allocateBlock(vertices:Int):Int {
		if (vertices <= 0)
			throw 'Vertex block must be nonempty';
		var order = 0, size = 1;
		while (size < vertices) {
			size <<= 1;
			order++;
		}
		var available = order;
		while (available < freeHead.length && freeHead[available] == -1)
			available++;
		var offset:Int;
		if (available < freeHead.length) {
			offset = freeHead[available];
			freeHead[available] = nextFree[offset];
			while (available > order) {
				available--;
				var right = offset + (1 << available);
				blockOrder[right] = available;
				blockActive[right] = 0;
				nextFree[right] = freeHead[available];
				freeHead[available] = right;
				blockOrder[offset] = available;
			}
		} else {
			offset = (count + size - 1) & ~(size - 1);
			if (offset + size > capacity)
				grow(Std.int(Math.max(capacity * 2.0, offset + size)));
			var gap = count;
			while (gap < offset) {
				var gapOrder = 0, gapSize = 1;
				while ((gap & ((gapSize << 1) - 1)) == 0 && gap + (gapSize << 1) <= offset) {
					gapSize <<= 1;
					gapOrder++;
				}
				blockOrder[gap] = gapOrder;
				blockActive[gap] = 0;
				nextFree[gap] = freeHead[gapOrder];
				freeHead[gapOrder] = gap;
				gap += gapSize;
			}
			count = offset + size;
		}
		blockOrder[offset] = order;
		blockActive[offset] = 1;
		blockRefs[offset] = 0;
		return offset;
	}

	public function generationAt(offset:Int):Int {
		return blockGeneration[offset];
	}

	public function isLiveBlock(offset:Int, generation:Int):Bool {
		return offset >= 0 && offset < count && blockOrder[offset] >= 0 && blockActive[offset] != 0 && blockGeneration[offset] == generation;
	}

	public inline function hasLiveBlock(offset:Int):Bool {
		return offset >= 0 && offset < count && blockOrder[offset] >= 0 && blockActive[offset] != 0;
	}

	public function retainBlock(offset:Int):Void {
		if (offset < 0 || offset >= count || blockOrder[offset] < 0 || blockActive[offset] == 0)
			throw 'Invalid vertex block';
		blockRefs[offset]++;
	}

	public function releaseBlock(offset:Int):Void {
		if (offset < 0 || offset >= count || blockOrder[offset] < 0 || blockActive[offset] == 0 || blockRefs[offset] <= 0)
			throw 'Invalid vertex block release';
		if (--blockRefs[offset] != 0)
			return;
		blockGeneration[offset]++;
		var order = blockOrder[offset];
		blockActive[offset] = 0;
		// Merge only with a free block of the same size at the buddy offset.
		while (order < 30) {
			var buddy = offset ^ (1 << order);
			if (buddy >= count || blockOrder[buddy] != order || blockActive[buddy] != 0)
				break;
			var previous = -1, current = freeHead[order];
			while (current != -1 && current != buddy) {
				previous = current;
				current = nextFree[current];
			}
			if (current == -1)
				break;
			if (previous == -1)
				freeHead[order] = nextFree[buddy];
			else
				nextFree[previous] = nextFree[buddy];
			blockOrder[offset] = -1;
			blockOrder[buddy] = -1;
			offset = offset < buddy ? offset : buddy;
			order++;
			blockOrder[offset] = order;
		}
		nextFree[offset] = freeHead[order];
		freeHead[order] = offset;
	}

	public inline function pushVertex(x:Single, y:Single, z:Single = 0.0):Int {
		if (count >= capacity)
			grow(capacity * 2);
		if (!Math.isFinite(x) || !Math.isFinite(y) || !Math.isFinite(z))
			throw 'Vertex coordinates must be finite';
		var idx = count++;
		blockOrder[idx] = -2;
		vx[idx] = x;
		vy[idx] = y;
		vz[idx] = z;
		return idx;
	}

	public inline function getVertex(idx:Int):Vec3 {
		return new Vec3(vx[idx], vy[idx], vz[idx]);
	}
}
