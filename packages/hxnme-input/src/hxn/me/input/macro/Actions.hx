package hxn.me.input.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;

/**
	Reads the bindings of an action set at compile time, for `Input.create`.
	Each binding becomes an integer in the table of the set. Names that are
	not a key, a button or an axis of hxn-window are compile errors at the
	metadata.
**/
class Actions {
	static inline final KEY = 1;
	static inline final MOUSE = 2;
	static inline final BUTTON = 3;
	static inline final AXIS = 4;
	static inline final KEY_NEGATIVE = 5;
	static inline final KEY_POSITIVE = 6;
	static inline final SHORTCUT = 7;

	// The modifiers of a shortcut, as bits of the window's modifier state.
	static final MODIFIERS = ["Shift" => 1, "Control" => 2, "Alt" => 4, "Super" => 8];

	// The kinds of the parts of a shortcut, in the high bits of each part.
	static inline final PART_KEY = 0;
	static inline final PART_MODIFIER = 1;
	static inline final PART_CHARACTER = 2;

	static final MOUSE_BUTTONS = ["Left", "Right", "Middle", "Back", "Forward"];

	/** The expression that `Input.create()` becomes, for the expected `Input<A>`. **/
	public static function create():Expr {
		var pos = Context.currentPos();
		var set = switch Context.getExpectedType() {
			case TAbstract(_.get() => {pack: ["hxn", "me", "input"], name: "Input"}, [set]): set;
			case _: Context.error("Input.create() needs the expected type Input<A>", pos);
		}
		var actions = switch Context.follow(set) {
			case TAbstract(a, _) if (a.get().meta.has(":actions")): a.get();
			case _: Context.error('`${TypeTools.toString(set)}` is not an action set: mark an enum abstract over Int with @:actions', pos);
		}
		var path = actions.pack.concat([actions.name]).join(".");
		var keys = values("hxn.window.KeyCode");
		var buttons = values("hxn.window.GamepadButton");
		var axes = values("hxn.window.GamepadAxis");
		var fields = [for (field in actions.impl.get().statics.get()) if (field.meta.has(":value")) field];
		fields.sort((a, b) -> number(a, path) - number(b, path));
		var table:Array<Expr> = [];
		var shortcuts:Array<Expr> = [];
		for (field in fields) {
			var index = number(field, path);
			if (index != table.length)
				Context.error('$path.${field.name} is $index: an action set numbers its actions from 0 without gaps', field.pos);
			var codes:Array<Int> = [];
			for (entry in field.meta.get()) {
				switch entry.name {
					case ":keys":
						for (param in entry.params)
							codes.push(KEY << 16 | code(param, keys, "a key of hxn.window.KeyCode"));
					case ":mouse":
						for (param in entry.params) {
							var index = MOUSE_BUTTONS.indexOf(name(param));
							if (index < 0)
								Context.error('`${name(param)}` is not a mouse button: use ${MOUSE_BUTTONS.join(", ")}', param.pos);
							codes.push(MOUSE << 16 | index);
						}
					case ":buttons":
						for (param in entry.params)
							codes.push(BUTTON << 16 | switch name(param) {
								// Confirm and Cancel stand for a different button on each family.
								case "Confirm": 100;
								case "Cancel": 101;
								case _: code(param, buttons, "a button of hxn.window.GamepadButton, or Confirm or Cancel: bind buttons by position, such as North, and show labels with Gamepads.label");
							});
					case ":axis":
						for (param in entry.params)
							codes.push(AXIS << 16 | code(param, axes, "an axis of hxn.window.GamepadAxis"));
					case ":shortcut":
						if (entry.params.length < 2)
							Context.error("@:shortcut takes two or more keys, held together, such as @:shortcut(Control, KeyS)", entry.pos);
						var parts:Array<Expr> = [];
						for (param in entry.params) {
							var key = name(param);
							if (MODIFIERS.exists(key)) {
								parts.push(macro $v{PART_MODIFIER << 16 | MODIFIERS.get(key)});
								continue;
							}
							var physical = code(param, keys, "a key of hxn.window.KeyCode, or Control, Shift, Alt or Super");
							// Letters and digits match the character that the key types, so
							// that a shortcut follows the keyboard layout.
							var letter = ~/^Key([A-Z])$/;
							var digit = ~/^Digit([0-9])$/;
							var part = if (letter.match(key)) PART_CHARACTER << 16 | letter.matched(1).toLowerCase().charCodeAt(0) else if (digit.match(key))
								PART_CHARACTER << 16 | digit.matched(1).charCodeAt(0) else PART_KEY << 16 | physical;
							parts.push(macro $v{part});
						}
						codes.push(SHORTCUT << 16 | shortcuts.length);
						shortcuts.push(macro $a{parts});
					case ":keyAxis":
						if (entry.params.length != 2)
							Context.error("@:keyAxis takes two keys: the key for -1, then the key for 1", entry.pos);
						codes.push(KEY_NEGATIVE << 16 | code(entry.params[0], keys, "a key of hxn.window.KeyCode"));
						codes.push(KEY_POSITIVE << 16 | code(entry.params[1], keys, "a key of hxn.window.KeyCode"));
					case _:
				}
			}
			var items = [for (c in codes) macro $v{c}];
			table.push(macro $a{items});
		}
		var type = Context.toComplexType(Context.getExpectedType());
		return macro(cast new hxn.me.input.InputState([$a{table}], [$a{shortcuts}]) : $type);
	}

	// The values of the enum abstract `path`, by name.
	static function values(path:String):Map<String, Int> {
		var out = new Map<String, Int>();
		switch Context.getType(path) {
			case TAbstract(a, _):
				for (field in a.get().impl.get().statics.get())
					if (field.meta.has(":value"))
						out.set(field.name, number(field, path));
			case _:
		}
		return out;
	}

	static function number(field:ClassField, path:String):Int {
		var expr = field.expr();
		while (expr != null)
			switch expr.expr {
				case TConst(TInt(value)):
					return value;
				case TCast(inner, _) | TParenthesis(inner) | TMeta(_, inner):
					expr = inner;
				case _:
					break;
			}
		return Context.error('$path.${field.name} needs an integer value', field.pos);
	}

	static function code(param:Expr, known:Map<String, Int>, kind:String):Int {
		var key = name(param);
		if (!known.exists(key))
			Context.error('`$key` is not $kind', param.pos);
		return known.get(key);
	}

	static function name(param:Expr):String {
		return switch param.expr {
			case EConst(CIdent(name)): name;
			case EField(_, name): name;
			case _: Context.error("name a key, a button or an axis here", param.pos);
		}
	}
}
#end
