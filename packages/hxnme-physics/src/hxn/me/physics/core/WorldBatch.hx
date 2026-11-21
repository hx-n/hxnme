package hxn.me.physics.core;

import sys.thread.FixedThreadPool;
import sys.thread.Lock;
import sys.thread.Mutex;

/**
 * Steps many independent worlds together, such as one per copy of a
 * training environment. Each worker takes a contiguous run of the worlds
 * and steps them one after another, calling `beforeStep` and `afterStep`
 * for each on the worker that steps it, so per-world work (applying actions,
 * reading observations) runs in parallel too.
 *
 * ```haxe
 * var batch = new WorldBatch(4);
 * for (env in envs) batch.add(env.world);
 * batch.beforeStep = (i, world) -> envs[i].act();
 * batch.step(1 / 60);
 * ```
 *
 * A world steps exactly as it would alone, whichever worker it lands on.
 * The callbacks must touch only their own world and its environment. Worlds
 * in a batch should not have island workers of their own. With one worker
 * everything runs on the calling thread. Stepping allocates nothing.
 */
class WorldBatch {
	public var worlds(default, null):Array<World> = [];
	public var workers(default, null):Int;

	/** Called with a world's index and the world just before it steps, on the thread stepping it. */
	public var beforeStep:Null<(Int, World) -> Void> = null;

	/** Called with a world's index and the world just after it steps, on the thread stepping it. */
	public var afterStep:Null<(Int, World) -> Void> = null;

	var dt:Float = 0.0;
	var pool:Null<FixedThreadPool> = null;
	var jobs:Array<Void->Void> = [];
	var done:Lock;
	var errorMutex:Mutex;
	var failure:Dynamic = null;

	public function new(workers:Int = 4) {
		if (workers < 1)
			throw 'A batch needs at least one worker';
		this.workers = workers;
		done = new Lock();
		errorMutex = new Mutex();
		if (workers > 1) {
			pool = new FixedThreadPool(workers);
			for (worker in 0...workers) {
				// Built once, so a step dispatches without creating closures.
				var lane = worker;
				jobs.push(function() {
					try {
						stepSlice(lane);
					} catch (error:Dynamic) {
						errorMutex.acquire();
						failure = error;
						errorMutex.release();
					}
					done.release();
				});
			}
		}
	}

	/** Adds a world and returns its index. */
	public function add(world:World):Int {
		worlds.push(world);
		return worlds.length - 1;
	}

	/** Steps every world once by `dt`. Rethrows the first error any world raised. */
	public function step(dt:Float):Void {
		this.dt = dt;
		if (pool == null || worlds.length < 2) {
			for (i in 0...worlds.length)
				stepOne(i);
			return;
		}
		failure = null;
		var used = workers < worlds.length ? workers : worlds.length;
		for (worker in 0...used)
			pool.run(jobs[worker]);
		for (_ in 0...used)
			done.wait();
		if (failure != null)
			throw failure;
	}

	/** Stops the workers. The batch steps on the calling thread afterwards. */
	public function shutdown():Void {
		if (pool != null)
			pool.shutdown();
		pool = null;
	}

	function stepSlice(worker:Int):Void {
		var n = worlds.length, used = workers < n ? workers : n;
		var start = Std.int(worker * n / used),
			end = Std.int((worker + 1) * n / used);
		for (i in start...end)
			stepOne(i);
	}

	inline function stepOne(i:Int):Void {
		var w = worlds[i];
		if (beforeStep != null)
			beforeStep(i, w);
		w.step(dt);
		if (afterStep != null)
			afterStep(i, w);
	}
}
