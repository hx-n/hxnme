package hxn.me.physics.island;

import hxn.me.math.Vec3;
import hxn.me.physics.core.World;
import hxn.me.physics.collision.NarrowPhase.ContactManifoldPool;
import hxn.me.physics.collision.PairScratch;
import hxn.me.WorkerPool;

class ParallelIslandSolver {
	var world:World;
	var pool:WorkerPool;
	var partition:IslandPartition;
	var workerCount:Int;

	public var minConstraintsPerIsland(default, null):Int;
	public var minPairsPerWorker(default, null):Int;

	// These fields hold the jobs, so a substep starts them without making
	// closures, and the arguments of a solve.
	var laneJob:Int->Void;
	var collideJob:Int->Void;
	var solveJobs = 0;
	var solveIterations = 0;
	// In the collision jobs, each worker tests one contiguous slice of the broadphase pairs.
	var pairScratch:Array<PairScratch> = [];
	var pairContacts:Array<ContactManifoldPool> = [];
	var pairStart:Array<Int> = [];
	var pairEnd:Array<Int> = [];
	var mergeNormal:Vec3 = new Vec3();
	var mergePoint:Vec3 = new Vec3();

	public function new(world:World, workerCount:Int, minConstraintsPerIsland:Int, minPairsPerWorker:Int) {
		if (workerCount < 2 || minConstraintsPerIsland < 1 || minPairsPerWorker < 0)
			throw 'Invalid island worker configuration';
		this.world = world;
		this.workerCount = workerCount;
		this.minConstraintsPerIsland = minConstraintsPerIsland;
		this.minPairsPerWorker = minPairsPerWorker;
		for (worker in 0...workerCount) {
			pairScratch.push(new PairScratch());
			pairContacts.push(new ContactManifoldPool(world.contacts.maxContacts));
			pairStart.push(0);
			pairEnd.push(0);
		}
		partition = new IslandPartition(world.bodyCapacity, world.contacts.capacity, world.joints.capacity);
		world.solver.configureIslandWorkers(workerCount);
		pool = new WorkerPool(workerCount);
		laneJob = runLane;
		collideJob = collideSlice;
	}

	/** Makes the partition for the world's present capacities. It is rebuilt every substep. */
	public function resize():Void
		partition = new IslandPartition(world.bodyCapacity, world.contacts.capacity, world.joints.capacity);

	public function mayDispatch():Bool {
		return world.contacts.count + world.joints.count >= minConstraintsPerIsland * 2.0;
	}

	/** Partitions the colored contacts by island, or returns null when the substep stays serial. */
	public function plan():Null<IslandPartition> {
		if (world.islands.islandCount < 2
			|| world.contacts.count + world.joints.count < minConstraintsPerIsland * 1.0 * world.islands.islandCount)
			return null;
		partition.build(world, world.solver.graph);
		return partition.activeCount < 2 ? null : partition;
	}

	/** Solves the partition returned by `plan`, after the solver has prepared rows in its order. */
	public function solve(iterations:Int):Void {
		if (world.joints.count > 0)
			for (index in 0...partition.activeCount) {
				var task = partition.tasks[index];
				world.joints.sortByColor(partition.jointIndices, task.jointStart, task.jointCount);
			}
		solveJobs = Std.int(Math.min(workerCount, partition.activeCount));
		solveIterations = iterations;
		// Each task owns its dynamic-body writes. Shared supports are read-only.
		pool.run(solveJobs, laneJob);
	}

	/**
	 * Tests this segment's broadphase pairs on the workers when there are
	 * enough of them, then merges the contacts in pair order. Returns false and
	 * leaves the pairs untested when the segment stays serial.
	 */
	public function collidePairs():Bool {
		var pairs = world.broadPhase.pairCount;
		if (minPairsPerWorker == 0 || pairs < minPairsPerWorker * workerCount)
			return false;
		var slice = Std.int((pairs + workerCount - 1) / workerCount);
		for (worker in 0...workerCount) {
			pairStart[worker] = worker * slice;
			pairEnd[worker] = Std.int(Math.min(pairs, (worker + 1) * slice));
		}
		pool.run(workerCount, collideJob);
		var contacts = world.contacts;
		var normal = mergeNormal, point = mergePoint;
		for (worker in 0...workerCount) {
			var found = pairContacts[worker];
			for (c in 0...found.count) {
				normal.x = found.normalX[c];
				normal.y = found.normalY[c];
				normal.z = found.normalZ[c];
				point.x = found.pointX[c];
				point.y = found.pointY[c];
				point.z = found.pointZ[c];
				contacts.addContact(found.bodyA[c], found.bodyB[c], found.shapeA[c], found.shapeB[c], found.featureId[c], normal, point, found.penetration[c]);
				world.wakeContactBodies(found.bodyA[c], found.bodyB[c]);
			}
		}
		return true;
	}

	function collideSlice(worker:Int):Void {
		var out = pairContacts[worker];
		out.clear();
		var scratch = pairScratch[worker];
		for (i in pairStart[worker]...pairEnd[worker])
			world.collideOne(i, scratch, out);
	}

	function runLane(lane:Int):Void {
		var index = lane, jobs = solveJobs, iterations = solveIterations;
		while (index < partition.activeCount) {
			world.solver.solveIsland(index, partition.tasks[index], iterations, lane);
			index += jobs;
		}
	}

	public function shutdown():Void {
		pool.shutdown();
	}
}
