import hxn.me.physics.core.WorldBatch;

/**
	Steps 16 independent worlds on a batch, and one world of 64 separate chains
	on island workers, for each worker count. Prints one JSON line per run.
**/
class WorkerScalingBench {
	static final COUNTS = [1, 2, 4, 8, 16];
	static inline var DT = 1.0 / 60;

	static function best(step:Void->Void):Float {
		for (_ in 0...60)
			step();
		var best = Math.POSITIVE_INFINITY;
		for (_ in 0...5) {
			var start = haxe.Timer.stamp();
			for (_ in 0...30)
				step();
			best = Math.min(best, (haxe.Timer.stamp() - start) * 1000 / 30);
		}
		return best;
	}

	static function main():Void {
		for (workers in COUNTS) {
			var batch = new WorldBatch(workers);
			for (_ in 0...16)
				batch.add(new HingeChain(true, true, 4).world);
			var ms = best(() -> batch.step(DT));
			batch.shutdown();
			Sys.println(haxe.Json.stringify({kind: "batch", workers: workers, worlds: 16, bestMs: ms}));
		}
		for (collide in [false, true])
			for (workers in COUNTS) {
				var world = new HingeChain(true, true, 64).world;
				if (workers > 1)
					world.enableParallelIslands(workers, 1, collide ? 1 : 0);
				var ms = best(() -> world.step(DT));
				if (workers > 1)
					world.disableParallelIslands();
				Sys.println(haxe.Json.stringify({kind: collide ? "islands+collide" : "islands", workers: workers, chains: 64, bestMs: ms}));
			}
	}
}
