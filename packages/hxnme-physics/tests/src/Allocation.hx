/** Measures how much a piece of code allocates, steadily despite the runtime's own background work. */
#if (cpp && !cppia)
@:cppFileCode('#include <hx/Telemetry.h>')
#end
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
	#elseif (cpp && !cppia)
	// hxcpp counts allocations only in a telemetry build (-D HXCPP_TELEMETRY):
	// each frame lists the size of every allocation since the previous frame.
	static var thread = -1;
	static var counted = 0.0;

	static function total():Float {
		if (thread < 0)
			thread = untyped __cpp__("__hxcpp_hxt_start_telemetry(true, true)");
		var added:Float = untyped __cpp__("({
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
			sum;
		})", thread);
		counted += added;
		return counted;
	}
	#elseif cppia
	// hxcpp telemetry faults on allocations made from script code. The engine
	// runs as compiled host code here, the same code the hxcpp checks measure.
	static var noted = false;

	static function total():Float {
		if (!noted) {
			noted = true;
			Sys.println("allocations: not measured in a CPPIA script; the hxcpp checks measure the same host code");
		}
		return 0;
	}
	#else
	static function total():Float {
		throw "Allocation is measured on HashLink and in hxcpp telemetry builds";
	}
	#end
}
