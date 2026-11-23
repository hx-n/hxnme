package hxn.me;

/**
	Runs jobs on a fixed set of worker threads. `run` calls a job once on each of the first
	`count` workers, with the worker's index, and returns when every call has
	finished. Starting a job allocates nothing, because each worker waits on a
	lock of its own. Store the job in a field: a closure made for each call
	allocates.

	In a program compiled without threads, `run` calls the job for each index
	in turn on the calling thread. So does an hxcpp program for Emscripten,
	because hxcpp does not start Haxe threads there.
**/
class WorkerPool {
	/** The number of workers. **/
	public final size:Int;

	#if (target.threaded && !emscripten)
	final starts:Array<sys.thread.Lock> = [];
	final done = new sys.thread.Lock();
	final errorMutex = new sys.thread.Mutex();
	var job:Null<Int->Void> = null;
	var failure:Null<haxe.Exception> = null;
	var stopping = false;
	#end

	public function new(size:Int) {
		if (size < 1)
			throw new haxe.exceptions.ArgumentException("size", 'a pool needs at least one worker, not $size');
		this.size = size;
		#if (target.threaded && !emscripten)
		for (_ in 0...size)
			starts.push(new sys.thread.Lock());
		for (worker in 0...size) {
			var lane = worker;
			sys.thread.Thread.create(() -> work(lane));
		}
		#end
	}

	/**
		Calls `job(worker)` for each worker below `count`, and returns when all
		of the calls have finished. Rethrows the first exception that a call
		threw.
	**/
	public function run(count:Int, job:Int->Void):Void {
		if (count < 0 || count > size)
			throw new haxe.exceptions.ArgumentException("count", 'a pool of $size workers cannot run $count jobs');
		#if (target.threaded && !emscripten)
		this.job = job;
		for (worker in 0...count)
			starts[worker].release();
		for (_ in 0...count)
			done.wait();
		this.job = null;
		if (failure != null) {
			var thrown = failure;
			failure = null;
			throw thrown;
		}
		#else
		for (worker in 0...count)
			job(worker);
		#end
	}

	/** Stops the workers. The pool cannot run jobs afterwards. **/
	public function shutdown():Void {
		#if (target.threaded && !emscripten)
		stopping = true;
		for (start in starts)
			start.release();
		for (_ in starts)
			done.wait();
		#end
	}

	#if (target.threaded && !emscripten)
	function work(lane:Int):Void {
		while (true) {
			starts[lane].wait();
			if (stopping) {
				done.release();
				return;
			}
			try {
				job(lane);
			} catch (error:haxe.Exception) {
				errorMutex.acquire();
				if (failure == null)
					failure = error;
				errorMutex.release();
			}
			done.release();
		}
	}
	#end
}
