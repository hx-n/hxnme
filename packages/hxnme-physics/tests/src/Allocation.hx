/** `Allocation` measures how much a piece of code allocates, with steady results despite the background work of the runtime. */
#if (cpp && !cppia && HXCPP_TELEMETRY)
@:cppFileCode('#include <hx/Telemetry.h>')
#end
class Allocation {
	#if macro
	/**
	 * Turns on hxcpp telemetry when hxcpp compiles a native program, where
	 * telemetry counts allocations. Telemetry does not start under Emscripten,
	 * and it faults on allocations made from CPPIA script code, so those
	 * targets go without it. To run it, add `--macro Allocation.setup()` to
	 * the program file.
	 */
	public static function setup():Void {
		var context = haxe.macro.Context;
		if (context.defined("cpp") && !context.defined("cppia") && !context.defined("emscripten"))
			haxe.macro.Compiler.define("HXCPP_TELEMETRY");
	}
	#end

	/**
	 * Returns the least that `run` allocated over `windows` calls, less the
	 * cost of reading the statistics. Code that allocates does so on every
	 * call, while the background threads of the runtime add only to some
	 * windows, so the least is the code's own.
	 */
	public static function least(run:Void->Void, windows:Int = 5):Float {
		var best = Math.POSITIVE_INFINITY;
		for (_ in 0...windows) {
			var empty = total();
			var reading = total() - empty;
			var before = total();
			run();
			var used = total() - before - reading;
			if (used < best) best = used;
		}
		return best < 0 ? 0 : best;
	}

	#if hl
	static inline function total():Float {
		return hl.Gc.stats().totalAllocated;
	}
	#elseif (cpp && !cppia && HXCPP_TELEMETRY)
	// hxcpp counts allocations only when it compiles with telemetry
	// (-D HXCPP_TELEMETRY). Each frame lists the size of every allocation since
	// the previous frame. hxcpp finds the frames by thread number. After worker
	// threads have run, the main thread's number can find another thread's
	// stack, or none. Reading through it counts nothing or reads freed memory,
	// so counting stops when the number no longer finds this thread. Whether it
	// does depends on how the threads ran, so the note goes to stderr, which
	// output comparisons leave out.
	static var thread = -1;
	static var counted = 0.0;
	static var lost = false;

	static function total():Float {
		if (thread < 0)
			thread = untyped __cpp__("__hxcpp_hxt_start_telemetry(true, true)");
		if (!lost && !untyped __cpp__("(hx::StackContext::getStackForId({0}) == hx::StackContext::getCurrent())", thread)) {
			lost = true;
			Sys.stderr().writeString("allocations: no longer measured: hxcpp's telemetry no longer finds this thread\n");
		}
		if (lost)
			return counted;
		// An immediately invoked lambda, because MSVC has no statement expressions.
		var added:Float = untyped __cpp__("[&]() -> double {
			__hxcpp_hxt_stash_telemetry();
			TelemetryFrame *frame = __hxcpp_hxt_dump_telemetry({0});
			double sum = 0;
			if (frame && frame->allocation_data) {
				std::vector<int> &data = *frame->allocation_data;
				for (size_t i = 0; i < data.size();) {
					if (data[i] == 0) { sum += data[i + 3]; i += 5; }
					else if (data[i] == 2) { sum += data[i + 3]; i += 4; }
					else i += 2;
				}
			}
			return sum;
		}()", thread);
		counted += added;
		return counted;
	}
	#elseif cpp
	// hxcpp telemetry faults on allocations made from CPPIA script code, and
	// does not start under Emscripten. The native hxcpp checks measure the
	// same engine code.
	static var noted = false;

	static function total():Float {
		if (!noted) {
			noted = true;
			Sys.println(#if cppia "allocations: not measured in a CPPIA script; the hxcpp checks measure the same host code" #else "allocations: not measured without HXCPP_TELEMETRY; the native hxcpp checks measure the same code" #end);
		}
		return 0;
	}
	#else
	static function total():Float {
		throw "Allocation is measured on HashLink and in hxcpp telemetry builds";
	}
	#end
}
