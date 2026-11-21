/** Measures how much a piece of code allocates, steadily despite the runtime's own background work. */
class Allocation {
	/**
	 * The least that `run` allocated over `windows` calls, less what reading
	 * the statistics itself costs. Code that allocates does so on every call,
	 * while the runtime's background threads only add to some windows, so the
	 * least is the code's own.
	 */
	public static function least(run:Void->Void, windows:Int = 5):Float {
		var best = Math.POSITIVE_INFINITY;
		for (_ in 0...windows) {
			var empty = hl.Gc.stats().totalAllocated;
			var reading = hl.Gc.stats().totalAllocated - empty;
			var before = hl.Gc.stats().totalAllocated;
			run();
			var used = hl.Gc.stats().totalAllocated - before - reading;
			if (used < best) best = used;
		}
		return best < 0 ? 0 : best;
	}
}
