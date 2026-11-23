package hxn.me.project;

/**
	Reads the TOML that hxnme's project files use: tables, dotted keys,
	strings, integers, floats, booleans, and arrays and inline tables of
	those. Dates and arrays of tables are rejected with an error that reports
	the line. The result is an anonymous structure of `String`, `Int`,
	`Float`, `Bool`, `Array<Dynamic>` and nested structures.
**/
class Toml {
	var text:String;
	var at = 0;
	var line = 1;
	var source:String;

	function new(text:String, source:String) {
		this.text = text;
		this.source = source;
	}

	/** Parses `text`. `source` identifies the file in error messages. **/
	public static function parse(text:String, source = "TOML"):Dynamic {
		return new Toml(text, source).document();
	}

	function document():Dynamic {
		var root = {};
		var table:Dynamic = root;
		var headers = [];
		while (true) {
			skipBlank();
			if (at >= text.length)
				return root;
			if (peek() == "[".code) {
				if (text.charCodeAt(at + 1) == "[".code)
					fail("arrays of tables are not supported");
				at++;
				spaces();
				var path = key();
				var name = path.join(".");
				if (headers.contains(name))
					fail('the table `$name` is defined twice');
				headers.push(name);
				table = into(root, path);
				spaces();
				expect("]".code);
			} else {
				var path = key();
				spaces();
				expect("=".code);
				spaces();
				assign(table, path, value());
			}
			endOfLine();
		}
	}

	// The table at `path` under `table`, created where missing.
	function into(table:Dynamic, path:Array<String>):Dynamic {
		for (i in 0...path.length) {
			var name = path[i];
			var next:Dynamic = Reflect.field(table, name);
			if (next == null) {
				next = {};
				Reflect.setField(table, name, next);
			} else if (!Reflect.isObject(next) || Std.isOfType(next, String) || Std.isOfType(next, Array))
				fail('`${path.join(".")}` is already a value');
			table = next;
		}
		return table;
	}

	function assign(table:Dynamic, path:Array<String>, value:Dynamic) {
		var parent = into(table, path.slice(0, path.length - 1));
		var name = path[path.length - 1];
		if (Reflect.hasField(parent, name))
			fail('`${path.join(".")}` is set twice');
		Reflect.setField(parent, name, value);
	}

	function key():Array<String> {
		var path = [];
		while (true) {
			spaces();
			path.push(switch peek() {
				case '"'.code: basic();
				case "'".code: literal();
				case _: bare();
			});
			spaces();
			if (peek() != ".".code)
				return path;
			at++;
		}
	}

	function bare():String {
		var start = at;
		while (at < text.length) {
			var c = peek();
			if ((c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || (c >= "0".code && c <= "9".code) || c == "_".code
				|| c == "-".code)
				at++;
			else
				break;
		}
		if (at == start)
			fail("expected a key");
		return text.substring(start, at);
	}

	function value():Dynamic {
		return switch peek() {
			case '"'.code: basic();
			case "'".code: literal();
			case "[".code: array();
			case "{".code: table();
			case "t".code | "f".code: boolean();
			case _: number();
		}
	}

	function basic():String {
		if (text.substr(at, 3) == '"""')
			fail("multi-line strings are not supported");
		at++;
		var out = new StringBuf();
		while (true) {
			if (at >= text.length || peek() == "\n".code)
				fail("unterminated string");
			var c = text.charCodeAt(at++);
			if (c == '"'.code)
				return out.toString();
			if (c != "\\".code) {
				out.addChar(c);
				continue;
			}
			var e = text.charCodeAt(at++);
			switch e {
				case '"'.code: out.add('"');
				case "\\".code: out.add("\\");
				case "n".code: out.add("\n");
				case "t".code: out.add("\t");
				case "r".code: out.add("\r");
				case "u".code:
					out.addChar(Std.parseInt("0x" + text.substr(at, 4)));
					at += 4;
				case _: fail("unknown escape in a string");
			}
		}
	}

	function literal():String {
		if (text.substr(at, 3) == "'''")
			fail("multi-line strings are not supported");
		var end = text.indexOf("'", at + 1);
		var newline = text.indexOf("\n", at + 1);
		if (end < 0 || (newline >= 0 && newline < end))
			fail("unterminated string");
		var s = text.substring(at + 1, end);
		at = end + 1;
		return s;
	}

	function array():Array<Dynamic> {
		at++;
		var items:Array<Dynamic> = [];
		while (true) {
			skipBlank();
			if (peek() == "]".code) {
				at++;
				return items;
			}
			items.push(value());
			skipBlank();
			if (peek() == ",".code)
				at++;
			else if (peek() != "]".code)
				fail("expected `,` or `]` in an array");
		}
	}

	function table():Dynamic {
		at++;
		var table = {};
		spaces();
		if (peek() == "}".code) {
			at++;
			return table;
		}
		while (true) {
			var path = key();
			spaces();
			expect("=".code);
			spaces();
			assign(table, path, value());
			spaces();
			if (peek() == "}".code) {
				at++;
				return table;
			}
			expect(",".code);
		}
	}

	function boolean():Bool {
		if (text.substr(at, 4) == "true") {
			at += 4;
			return true;
		}
		if (text.substr(at, 5) == "false") {
			at += 5;
			return false;
		}
		return fail("expected a value");
	}

	function number():Dynamic {
		var start = at;
		while (at < text.length && ~/[0-9A-Za-z_+.\-]/.match(text.charAt(at)))
			at++;
		var word = StringTools.replace(text.substring(start, at), "_", "");
		if (word == "")
			fail("expected a value");
		if (~/^[+-]?[0-9]+$/.match(word))
			return Std.parseInt(word);
		if (~/^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.match(word))
			return Std.parseFloat(word);
		if (~/^[0-9]{4}-[0-9]{2}-[0-9]{2}/.match(word))
			fail("dates are not supported");
		return fail('`$word` is not a value');
	}

	inline function peek():Int {
		return at < text.length ? text.charCodeAt(at) : -1;
	}

	function expect(c:Int) {
		if (peek() != c)
			fail('expected `${String.fromCharCode(c)}`');
		at++;
	}

	function spaces() {
		while (peek() == " ".code || peek() == "\t".code)
			at++;
	}

	// Skips spaces, comments and line ends.
	function skipBlank() {
		while (at < text.length) {
			var c = peek();
			if (c == " ".code || c == "\t".code || c == "\r".code)
				at++;
			else if (c == "\n".code) {
				at++;
				line++;
			} else if (c == "#".code)
				while (at < text.length && peek() != "\n".code)
					at++;
			else
				break;
		}
	}

	function endOfLine() {
		spaces();
		if (peek() == "#".code)
			while (at < text.length && peek() != "\n".code)
				at++;
		if (peek() == "\r".code)
			at++;
		if (at < text.length && peek() != "\n".code)
			fail("expected the end of the line");
	}

	function fail(message:String):Dynamic {
		throw '$source:$line: $message';
	}
}
