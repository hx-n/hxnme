package hxn.me.physics.diagnostics;

enum abstract Severity(String) to String {
	var Error = "error";
	var Warning = "warning";
	var Info = "info";
}

/** `Diagnostic` records one finding: a stable code, where it is, what is wrong, and how to fix it. */
class Diagnostic {
	/** Holds a stable identifier, such as RIG_UNKNOWN_PARENT. Code can safely match on it. */
	public var code(default, null):String;

	public var severity(default, null):Severity;

	/** Holds the slash-separated path to the object, such as skeleton/bones/forearm/parent. */
	public var path(default, null):String;

	public var message(default, null):String;
	public var expected(default, null):Null<String>;
	public var actual(default, null):Null<String>;
	public var suggestion(default, null):Null<String>;

	public function new(code:String, severity:Severity, path:String, message:String, expected:Null<String> = null, actual:Null<String> = null,
			suggestion:Null<String> = null) {
		this.code = code;
		this.severity = severity;
		this.path = path;
		this.message = message;
		this.expected = expected;
		this.actual = actual;
		this.suggestion = suggestion;
	}
}

/**
 * `Diagnostics` collects the findings of building or validating something,
 * for both people and agents. It reports every problem at once. `toJson`
 * gives a machine-readable report, and `toText` gives a readable one.
 */
class Diagnostics {
	public var items(default, null):Array<Diagnostic> = [];

	public function new() {}

	public function add(code:String, severity:Severity, path:String, message:String, expected:Null<String> = null, actual:Null<String> = null,
			suggestion:Null<String> = null):Void {
		items.push(new Diagnostic(code, severity, path, message, expected, actual, suggestion));
	}

	public function error(code:String, path:String, message:String, ?expected:String, ?actual:String, ?suggestion:String):Void
		add(code, Error, path, message, expected, actual, suggestion);

	public function warning(code:String, path:String, message:String, ?expected:String, ?actual:String, ?suggestion:String):Void
		add(code, Warning, path, message, expected, actual, suggestion);

	public var hasErrors(get, never):Bool;

	function get_hasErrors():Bool {
		for (d in items)
			if (d.severity == Error)
				return true;
		return false;
	}

	public function count(severity:Severity):Int {
		var n = 0;
		for (d in items)
			if (d.severity == severity)
				n++;
		return n;
	}

	/** Returns the findings with `code`, for checks and tools that look for one problem. */
	public function withCode(code:String):Array<Diagnostic> {
		return [for (d in items) if (d.code == code) d];
	}

	/** Throws a readable summary when any finding is an error. */
	public function throwIfErrors():Void {
		if (hasErrors)
			throw toText();
	}

	/**
	 * Returns the report as JSON: {"errors":n,"warnings":n,"items":[{"code",...}]}.
	 * The field order is fixed and absent optional fields are left out, so
	 * equal reports produce equal text.
	 */
	public function toJson():String {
		var out = new StringBuf();
		out.add('{"errors":${count(Error)},"warnings":${count(Warning)},"items":[');
		for (i in 0...items.length) {
			var d = items[i];
			if (i > 0)
				out.add(",");
			out.add('{"code":${quote(d.code)},"severity":${quote(d.severity)},"path":${quote(d.path)},"message":${quote(d.message)}');
			if (d.expected != null)
				out.add(',"expected":${quote(d.expected)}');
			if (d.actual != null)
				out.add(',"actual":${quote(d.actual)}');
			if (d.suggestion != null)
				out.add(',"suggestion":${quote(d.suggestion)}');
			out.add("}");
		}
		out.add("]}");
		return out.toString();
	}

	/** Returns the report as text: one line per finding, then its suggestions indented beneath. */
	public function toText():String {
		if (items.length == 0)
			return "no problems found";
		var out = new StringBuf();
		for (d in items) {
			out.add('${d.severity} ${d.code} at ${d.path}: ${d.message}');
			if (d.expected != null || d.actual != null)
				out.add(' (expected ${d.expected == null ? "-" : d.expected}, got ${d.actual == null ? "-" : d.actual})');
			out.add("\n");
			if (d.suggestion != null)
				out.add('  fix: ${d.suggestion}\n');
		}
		out.add(plural(count(Error), "error") + ", " + plural(count(Warning), "warning"));
		return out.toString();
	}

	static function plural(n:Int, noun:String):String {
		return '$n $noun' + (n == 1 ? "" : "s");
	}

	/** Returns `text` as a JSON string literal. */
	public static function quote(text:String):String {
		var out = new StringBuf();
		out.add('"');
		for (i in 0...text.length) {
			var c = text.charCodeAt(i);
			switch (c) {
				case '"'.code:
					out.add('\\"');
				case '\\'.code:
					out.add('\\\\');
				case '\n'.code:
					out.add('\\n');
				case '\r'.code:
					out.add('\\r');
				case '\t'.code:
					out.add('\\t');
				default:
					if (c < 0x20)
						out.add('\\u' + StringTools.hex(c, 4))
					else
						out.addChar(c);
			}
		}
		out.add('"');
		return out.toString();
	}

	/** Formats `v` as fixed-point text with up to four decimals, no exponent and no negative zero. Returns null when `v` is not finite. */
	public static function number(v:Float):String {
		if (!Math.isFinite(v))
			return "null";
		var scaled = Math.fround(Math.abs(v) * 10000.0);
		if (scaled == 0.0)
			return "0";
		var whole = Math.ffloor(scaled / 10000.0);
		var fraction = Std.int(scaled - whole * 10000.0);
		var text = (v < 0.0 ? "-" : "") + (whole < 2147483648.0 ? Std.string(Std.int(whole)) : Std.string(whole));
		if (fraction == 0)
			return text;
		var digits = Std.string(fraction + 10000).substr(1);
		while (digits.charCodeAt(digits.length - 1) == "0".code)
			digits = digits.substr(0, digits.length - 1);
		return text + "." + digits;
	}

	/** Returns the candidate nearest `name` by edit distance, when it is close enough to be a likely typo. */
	public static function closest(name:String, candidates:Iterator<String>):Null<String> {
		var best:Null<String> = null, bestDistance = 3;
		for (candidate in candidates) {
			var distance = editDistance(name.toLowerCase(), candidate.toLowerCase());
			if (distance < bestDistance || distance == bestDistance && best != null && candidate < best) {
				best = candidate;
				bestDistance = distance;
			}
		}
		return best;
	}

	static function editDistance(a:String, b:String):Int {
		var previous = [for (j in 0...b.length + 1) j];
		for (i in 1...a.length + 1) {
			var current = [i];
			for (j in 1...b.length + 1) {
				var cost = a.charCodeAt(i - 1) == b.charCodeAt(j - 1) ? 0 : 1;
				current.push(Std.int(Math.min(Math.min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost)));
			}
			previous = current;
		}
		return previous[b.length];
	}
}
