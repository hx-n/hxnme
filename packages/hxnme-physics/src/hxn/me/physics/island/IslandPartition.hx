package hxn.me.physics.island;

import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.BodyType;
import hl.NativeArray;

class IslandTask {
	public var root:Int = -1;
	public var counts:NativeArray<Int>;
	public var offsets:NativeArray<Int>;
	public var cursors:NativeArray<Int>;
	public var jointStart:Int = 0;
	public var jointCount:Int = 0;

	public function new() {
		counts = new NativeArray<Int>(ConstraintGraph.COLOR_COUNT);
		offsets = new NativeArray<Int>(ConstraintGraph.COLOR_COUNT);
		cursors = new NativeArray<Int>(ConstraintGraph.COLOR_COUNT);
	}

	public function reset(root:Int):Void {
		this.root = root;
		jointCount = 0;
		for (color in 0...ConstraintGraph.COLOR_COUNT)
			counts[color] = 0;
	}
}

class IslandPartition {
	public var tasks:Array<IslandTask> = [];
	public var activeCount(default, null):Int = 0;
	public var contactCount(default, null):Int = 0;
	public var contactIndices:NativeArray<Int>;
	public var jointIndices:NativeArray<Int>;

	var rootToTask:NativeArray<Int>;
	var contactTask:NativeArray<Int>;
	var jointTask:NativeArray<Int>;
	var jointCursor:NativeArray<Int>;

	public function new(bodyCapacity:Int, contactCapacity:Int, jointCapacity:Int) {
		rootToTask = new NativeArray<Int>(bodyCapacity);
		contactTask = new NativeArray<Int>(contactCapacity);
		jointTask = new NativeArray<Int>(jointCapacity);
		contactIndices = new NativeArray<Int>(contactCapacity);
		jointIndices = new NativeArray<Int>(jointCapacity);
		jointCursor = new NativeArray<Int>(bodyCapacity);
	}

	function taskFor(world:World, a:Int, b:Int):Int {
		var movingBody = world.bodyType[a] == BodyType.Dynamic ? a : world.bodyType[b] == BodyType.Dynamic ? b : -1;
		if (movingBody < 0)
			return -1;
		var root = world.islands.root(movingBody);
		var index = rootToTask[root];
		if (index >= 0)
			return index;
		index = activeCount++;
		if (index == tasks.length)
			tasks.push(new IslandTask());
		tasks[index].reset(root);
		rootToTask[root] = index;
		return index;
	}

	public function build(world:World, graph:ConstraintGraph):Void {
		var needed = world.contacts.count;
		if (needed > contactTask.length) {
			var cap = contactTask.length < 4 ? 4 : contactTask.length;
			while (cap < needed)
				cap *= 2;
			contactTask = new NativeArray<Int>(cap);
			contactIndices = new NativeArray<Int>(cap);
		}
		activeCount = 0;
		for (body in 0...world.bodyCount)
			rootToTask[body] = -1;
		var contacts = world.contacts;
		for (c in 0...contacts.count) {
			var index = taskFor(world, contacts.bodyA[c], contacts.bodyB[c]);
			contactTask[c] = index;
			if (index >= 0)
				tasks[index].counts[graph.colors[c]]++;
		}
		var joints = world.joints;
		for (position in 0...joints.count) {
			var id = joints.activeIds[position];
			var index = taskFor(world, joints.bodyA[id], joints.bodyB[id]);
			jointTask[position] = index;
			if (index >= 0)
				tasks[index].jointCount++;
		}
		var contactOffset = 0;
		var jointOffset = 0;
		for (index in 0...activeCount) {
			var task = tasks[index];
			for (color in 0...ConstraintGraph.COLOR_COUNT) {
				task.offsets[color] = contactOffset;
				task.cursors[color] = contactOffset;
				contactOffset += task.counts[color];
			}
			task.jointStart = jointOffset;
			jointOffset += task.jointCount;
		}
		contactCount = contactOffset;
		for (index in 0...activeCount)
			jointCursor[index] = tasks[index].jointStart;
		for (c in 0...contacts.count) {
			var index = contactTask[c];
			if (index < 0)
				continue;
			var color = graph.colors[c];
			var task = tasks[index];
			contactIndices[task.cursors[color]++] = c;
		}
		for (position in 0...joints.count) {
			var index = jointTask[position];
			if (index >= 0)
				jointIndices[jointCursor[index]++] = joints.activeIds[position];
		}
	}
}
