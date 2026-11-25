package hxn.me.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;

private typedef Param = {
	var write:Bool;
	var type:Type;
	var key:String;
}

private typedef Ref = {
	var text:String;
	var pos:Position;
}

private typedef System = {
	var id:String;
	var owner:String;
	var name:String;
	var phase:String;
	var description:Null<String>;
	var after:Array<Ref>;
	var before:Array<Ref>;
	var params:Array<Param>;
	var pos:Position;
	var index:Int;
}

/**
	`Scheduler` generates `hxn.me.Schedule` from the systems of an app.
	Systems are static functions with `@:system`. The systems come from the
	classes that the app passes, from each plugin class, and from the classes
	that a plugin class lists with `@:systems`. Each phase gets one method that calls its
	systems directly, in an order that obeys every `before` and `after`.
	Where no constraint applies, the systems of the plugins come first, in
	plugin order. The systems of the app follow, in the order that the app
	passes their classes. The systems of one class keep their declaration order.
**/
class Scheduler {
	// Lists the phases of hxn.me.Phase, in the order that they run.
	static final PHASES = ["Start", "Begin", "Fixed", "Update", "Render"];

	// Lists the resources that every schedule has, and the public fields that hold them.
	static final KERNEL = [
		{key: "hxn.me.Time", field: "time"},
		{key: "hxn.me.Lifecycle", field: "lifecycle"},
		{key: "hxn.me.Display", field: "display"}
	];

	static var generated = false;

	/** Returns the expression that `hxn.me.App.run(classes)` becomes. **/
	public static function run(classes:Array<Expr>):Expr {
		var schedule = schedule(classes);
		var host = Registry.provider("hxn.me.Host");
		if (host == null)
			host = macro new hxn.me.HeadlessHost();
		return macro {
			hxn.me.Plugins.start();
			var schedule = $schedule;
			$host.run(new hxn.me.AppLoop(schedule, schedule.time, schedule.lifecycle, schedule.display));
		};
	}

	/** Returns the expression that `hxn.me.App.schedule(classes)` becomes. **/
	public static function schedule(classes:Array<Expr>):Expr {
		if (generated)
			Context.error("the app calls hxn.me.App.run or hxn.me.App.schedule once", Context.currentPos());
		generated = true;
		var owners:Array<String> = [];
		function own(path:String)
			if (!owners.contains(path))
				owners.push(path);
		for (plugin in Registry.pluginClasses()) {
			Context.getType(plugin);
			own(plugin);
			for (path in Registry.systemClasses(plugin))
				own(path);
		}
		for (expr in classes)
			own(classOf(expr, "hxn.me.App.schedule takes the classes that hold the app's systems"));
		var systems = [];
		for (owner in owners)
			collect(owner, systems);
		define(systems);
		return macro new hxn.me.Schedule();
	}

	/** Returns the path of the class that `expr` refers to. It types `expr` where `expr` appears. **/
	public static function classOf(expr:Expr, message:String):String {
		return switch Context.typeExpr(expr).expr {
			case TTypeExpr(TClassDecl(c)): path(c.get());
			case _: Context.error(message, expr.pos);
		}
	}

	static function path(c:{module:String, name:String}):String
		return typePath(c);

	/**
		Returns the path that refers to the type `t` in code. Its module is
		followed by its name when `t` is not the main type of its module, as for
		`spin.SpinPlugin.Spin`.
	**/
	static function typePath(t:{module:String, name:String}):String
		return t.module.split(".").pop() == t.name ? t.module : '${t.module}.${t.name}';

	// `@:access` matches a class by its package and name, not by its module.
	static function accessPath(owner:String):Array<String> {
		return switch Context.getType(owner) {
			case TInst(c, _): c.get().pack.concat([c.get().name]);
			case _: owner.split(".");
		}
	}

	// Adds the systems of the class `owner`, in declaration order.
	static function collect(owner:String, systems:Array<System>) {
		var c = switch Context.getType(owner) {
			case TInst(c, _): c.get();
			case _: Context.error('$owner is not a class', Context.currentPos());
		}
		for (field in c.fields.get())
			if (field.meta.has(":system"))
				Context.error('$owner.${field.name} is not static: a system is a static function', field.meta.extract(":system")[0].pos);
		for (field in c.statics.get()) {
			var meta = field.meta.extract(":system");
			if (meta.length == 0)
				continue;
			var id = '$owner.${field.name}';
			var at = meta[0].pos;
			if (meta.length > 1)
				Context.error('$id has more than one @:system', at);
			var args = switch [field.kind, Context.follow(field.type)] {
				case [FMethod(_), TFun(args, ret)]:
					if (!isVoid(ret))
						Context.error('$id returns a value: a system returns Void', at);
					args;
				case _: Context.error('$id is not a function: @:system marks a static function', at);
			}
			var system:System = {
				id: id,
				owner: owner,
				name: field.name,
				phase: null,
				description: null,
				after: [],
				before: [],
				params: [],
				pos: at,
				index: systems.length,
			};
			read(meta[0], system);
			for (arg in args) {
				var param = parameter(arg.t, at);
				if (param == null)
					Context.error('$id takes `${arg.name}:${TypeTools.toString(arg.t)}`: a system takes Res<T> or ResMut<T>', at);
				for (other in system.params)
					if (other.key == param.key)
						Context.error('$id takes ${param.key} twice', at);
				system.params.push(param);
			}
			systems.push(system);
		}
	}

	// Reads the phase, the constraints and the description from
	// `@:system(Phase, after = ..., before = ..., description = "...")`.
	static function read(meta:MetadataEntry, system:System) {
		if (meta.params.length == 0)
			Context.error('${system.id} has no phase: write @:system(${PHASES.join(" | ")})', meta.pos);
		var phase = dotted(meta.params[0]).split(".").pop();
		if (!PHASES.contains(phase))
			Context.error('`$phase` is not a phase: use ${PHASES.slice(0, -1).join(", ")} or ${PHASES[PHASES.length - 1]}', meta.params[0].pos);
		system.phase = phase;
		for (param in meta.params.slice(1)) {
			switch param.expr {
				case EBinop(OpAssign, {expr: EConst(CIdent(key))}, value) if (key == "after" || key == "before"):
					var values = switch value.expr {
						case EArrayDecl(values): values;
						case _: [value];
					}
					var refs = key == "after" ? system.after : system.before;
					for (value in values)
						refs.push({text: dotted(value), pos: value.pos});
				case EBinop(OpAssign, {expr: EConst(CIdent("description"))}, value):
					system.description = text(value, "description");
				case _:
					Context.error('@:system takes a phase, then `after = ...`, `before = ...` and `description = "..."`', param.pos);
			}
		}
	}

	/** Returns the string that `expr` holds. `key` identifies it in the error. **/
	public static function text(expr:Expr, key:String):String {
		return switch expr.expr {
			case EConst(CString(value)): value;
			case _: Context.error('`$key` takes a string', expr.pos);
		}
	}

	// Returns a dotted name: `move`, `Movement`, `game.Movement.move`.
	static function dotted(expr:Expr):String {
		return switch expr.expr {
			case EConst(CIdent(name)): name;
			case EField(owner, name): dotted(owner) + "." + name;
			case _: Context.error("name a system or a class of systems here", expr.pos);
		}
	}

	static function isVoid(type:Type):Bool {
		return switch Context.follow(type) {
			case TAbstract(_.get() => {pack: [], name: "Void"}, _): true;
			case _: false;
		}
	}

	// Returns the parameter that `type` declares, or null if a system cannot take `type`.
	static function parameter(type:Type, at:Position):Null<Param> {
		return switch Context.follow(type) {
			case TAbstract(_.get() => {pack: ["hxn", "me"], name: name}, [resource]) if (name == "Res" || name == "ResMut"):
				var key = TypeTools.toString(resource);
				switch Context.follow(resource) {
					case TInst(_.get() => c, _) if (!c.isInterface && c.kind.match(KNormal) && constructible(c)):
					case TAbstract(_.get() => a, _) if (a.impl != null && TypeTools.findField(a.impl.get(), "create", true) != null):
					case _:
						Context.error('`$key` cannot be a resource: a resource is a class whose constructor takes no arguments, or an abstract with a static `create()`', at);
				}
				{write: name == "ResMut", type: resource, key: key};
			case _: null;
		}
	}

	static function constructible(c:ClassType):Bool {
		if (c.constructor == null)
			return false;
		return switch Context.follow(c.constructor.get().type) {
			case TFun(args, _): Lambda.foreach(args, arg -> arg.opt);
			case _: false;
		}
	}

	// Returns the systems that `ref` refers to in the phase of `system`. `ref` is a
	// constraint of `system`.
	static function resolve(ref:Ref, system:System, systems:Array<System>):Array<System> {
		var text = ref.text;
		if (text.indexOf(".") < 0)
			for (other in systems)
				if (other.owner == system.owner && other.name == text)
					return checkPhase(other, ref, system);
		function names(full:String)
			return full == text || StringTools.endsWith(full, "." + text);
		var named = systems.filter(other -> names(other.id));
		var owners = [];
		for (other in systems)
			if (names(other.owner) && !owners.contains(other.owner))
				owners.push(other.owner);
		var count = named.length + owners.length;
		if (count == 0)
			Context.error('${system.id} refers to `$text`, which is no system of the app and no class of its systems', ref.pos);
		if (count > 1) {
			var all = named.map(s -> s.id).concat(owners);
			Context.error('${system.id} refers to `$text`, which could be ${all.join(" or ")}: write the full path', ref.pos);
		}
		if (named.length == 1)
			return checkPhase(named[0], ref, system);
		return systems.filter(other -> other.owner == owners[0] && other.phase == system.phase && other != system);
	}

	static function checkPhase(other:System, ref:Ref, system:System):Array<System> {
		if (other == system)
			Context.error('${system.id} refers to itself in a constraint', ref.pos);
		if (other.phase != system.phase)
			Context.error('${system.id} runs in ${system.phase}, and `${ref.text}` refers to ${other.id}, which runs in ${other.phase}', ref.pos);
		return [other];
	}

	// Returns the systems of one phase in run order. Each system comes after
	// the systems it must follow. Where the constraints permit more than one
	// order, the default order applies.
	static function order(phase:String, all:Array<System>):Array<System> {
		var systems = all.filter(s -> s.phase == phase);
		var before = new Map<Int, Array<Int>>();
		var waiting = new Map<Int, Int>();
		for (s in systems) {
			before.set(s.index, []);
			waiting.set(s.index, 0);
		}
		function edge(first:System, then:System) {
			var next = before.get(first.index);
			if (next.contains(then.index))
				return;
			next.push(then.index);
			waiting.set(then.index, waiting.get(then.index) + 1);
		}
		for (s in systems) {
			for (ref in s.after)
				for (other in resolve(ref, s, all))
					edge(other, s);
			for (ref in s.before)
				for (other in resolve(ref, s, all))
					edge(s, other);
		}
		var out = [];
		var left = systems.copy();
		while (left.length > 0) {
			var ready = Lambda.find(left, s -> waiting.get(s.index) == 0);
			if (ready == null)
				Context.error('the $phase systems are ordered in a cycle, each running before the next: ${cycle(left, before, all)}', left[0].pos);
			left.remove(ready);
			out.push(ready);
			for (index in before.get(ready.index))
				waiting.set(index, waiting.get(index) - 1);
		}
		return out;
	}

	// Returns a cycle in `left`. Each system in `left` waits on another one in `left`.
	static function cycle(left:Array<System>, before:Map<Int, Array<Int>>, all:Array<System>):String {
		var inLeft = [for (s in left) s.index];
		var path = [left[0].index];
		while (true) {
			var next = Lambda.find(before.get(path[path.length - 1]), i -> inLeft.contains(i));
			var seen = path.indexOf(next);
			if (seen >= 0)
				return path.slice(seen).concat([next]).map(i -> all[i].id).join(" -> ");
			path.push(next);
		}
	}

	static function define(systems:Array<System>) {
		var pos = Context.currentPos();
		var resources:Array<Param> = [];
		var users = new Map<String, {reads:Array<String>, writes:Array<String>}>();
		for (kernel in KERNEL) {
			resources.push({write: false, type: Context.getType(kernel.key), key: kernel.key});
			users.set(kernel.key, {reads: [], writes: []});
		}
		for (s in systems)
			for (p in s.params) {
				if (!users.exists(p.key)) {
					resources.push(p);
					users.set(p.key, {reads: [], writes: []});
				}
				(p.write ? users.get(p.key).writes : users.get(p.key).reads).push(s.id);
			}
		var fields:Array<Field> = [];
		var creates:Array<Expr> = [];
		var clears:Array<Expr> = [];
		var names = [];
		for (i in 0...resources.length) {
			var r = resources[i];
			var type = Context.toComplexType(r.type);
			var use = users.get(r.key);
			var kernel = Lambda.find(KERNEL, k -> k.key == r.key);
			var name = kernel == null ? 'resource$i' : kernel.field;
			names.push(name);
			fields.push({
				name: name,
				doc: '`${r.key}`. Read by: ${list(use.reads)}. Written by: ${list(use.writes)}.',
				access: [kernel == null ? APrivate : APublic, AFinal],
				kind: FVar(type, null),
				pos: pos,
			});
			var create = switch [Context.follow(r.type), type] {
				case [TAbstract(_.get() => a, _), _]:
					// Abstracts make their instance with `create()`, which can read
					// the type parameters from the expected type.
					var path = typePath(a).split(".");
					macro($p{path}.create() : $type);
				case [_, TPath(p)]: {expr: ENew(p, []), pos: pos};
				case _: throw "unreachable";
			}
			creates.push(macro $i{name} = $create);
			if (isEvents(r.type))
				clears.push(macro $i{name}.clear());
		}
		fields.push({
			name: "new",
			doc: "Creates the resources of the app's systems.",
			access: [APublic],
			kind: FFun({args: [], ret: null, expr: macro $b{creates}}),
			pos: pos,
		});
		var keys = [for (r in resources) r.key];
		for (phase in PHASES) {
			var calls:Array<Expr> = [];
			var lines = [];
			for (s in order(phase, systems)) {
				var args = [for (p in s.params) macro $i{names[keys.indexOf(p.key)]}];
				calls.push(macro $p{s.owner.split(".").concat([s.name])}($a{args}));
				var reads = [for (p in s.params) if (!p.write) p.key];
				var writes = [for (p in s.params) if (p.write) p.key];
				var described = s.description == null ? "" : '. ${s.description}';
				lines.push('\t${s.id}: reads ${list(reads)}, writes ${list(writes)}$described');
			}
			fields.push({
				name: phase.charAt(0).toLowerCase() + phase.substr(1),
				doc: lines.length == 0 ? 'Runs the $phase phase, which has no systems.' : 'Runs the $phase phase:\n' + lines.join("\n"),
				access: [APublic],
				kind: FFun({args: [], ret: macro :Void, expr: macro $b{calls}}),
				pos: pos,
			});
		}
		fields.push({
			name: "end",
			doc: "Ends the frame: clears each event queue, after `Render`.",
			access: [APublic],
			kind: FFun({args: [], ret: macro :Void, expr: macro $b{clears}}),
			pos: pos,
		});
		var owners = [];
		for (s in systems)
			if (!owners.contains(s.owner))
				owners.push(s.owner);
		var definition:TypeDefinition = {
			pack: ["hxn", "me"],
			name: "Schedule",
			doc: "The systems of the app in frame order, generated by hxnme at compile time.",
			meta: [for (owner in owners) {name: ":access", params: [macro $p{accessPath(owner)}], pos: pos}],
			kind: TDClass(null, [{pack: ["hxn", "me"], name: "Phases"}]),
			fields: fields,
			pos: pos,
		};
		Context.defineType(definition, "hxn.me.Generated");
		Dump.add(definition);
	}

	static function isEvents(type:Type):Bool {
		return switch Context.follow(type) {
			case TInst(_.get() => {pack: ["hxn", "me"], name: "Events"}, _): true;
			case _: false;
		}
	}

	static function list(names:Array<String>):String
		return names.length == 0 ? "nothing" : names.join(", ");
}
#end
