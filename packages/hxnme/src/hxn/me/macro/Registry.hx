package hxn.me.macro;

#if macro
import haxe.Json;
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import sys.FileSystem;
import sys.io.File;

private typedef Manifest = {
	var name:String;
	var plugin:String;
	var requires:Array<String>;
	var platforms:Array<String>;
	var file:String;
}

/**
	Generates `hxn.me.Plugins` at compile time from the plugins of the app.
	Each plugin's `extraParams.hxml` calls `add` with its haxelib name, for
	`-lib` and for `hxnme.toml` alike. Once the init macros have run, the
	registry reads each plugin's manifest, checks the requirements and the
	target, orders the plugins after the ones they require, and defines a
	class that creates and starts each plugin directly. `-D hxnme_dump` writes
	that class to a file.

	Plugin classes do not have to implement `hxn.me.Plugin` or the services
	they provide. The registry checks each plugin class against those
	interfaces by method name and type, and the generated code calls the
	class directly. Classes that implement them get the same checks.
**/
class Registry {
	static final RUNTIMES = ["hl", "cpp", "cppia"];
	static final KINDS = ["desktop", "wasm", "android", "ios"];

	static var names:Array<String> = [];
	static var manifests:Map<String, Manifest> = [];
	static var order:Array<String> = [];
	static var systems:Map<String, Array<String>> = [];
	static var descriptions:Map<String, String> = [];
	static var fields:Map<String, String> = [];
	static var providers:Map<String, String> = [];
	static var checked:Array<String> = [];
	static var installed = false;

	/** Generates `hxn.me.Plugins` once the init macros have run. **/
	public static function install() {
		if (installed)
			return;
		installed = true;
		Context.onAfterInitMacros(generate);
	}

	/** Registers the plugin of the haxelib `name`. **/
	public static function add(name:String) {
		install();
		if (!names.contains(name))
			names.push(name);
	}

	/**
		Checks a plugin class against its manifest, and records what its
		metadata declares. It runs on the plugin class of each manifest, and on
		each class that implements `hxn.me.Plugin`.
	**/
	public static function check():Array<Field> {
		var local = Context.getLocalClass().get();
		var path = local.pack.concat([local.name]).join(".");
		if (checked.contains(path))
			return null;
		checked.push(path);
		var meta = local.meta.extract(":plugin");
		if (meta.length != 1 || meta[0].params.length == 0) {
			for (manifest in manifests)
				if (manifest.plugin == path)
					Context.error('${manifest.file} specifies $path as the plugin class of `${manifest.name}`: mark the class with @:plugin("${manifest.name}")', local.pos);
			Context.error('$path implements hxn.me.Plugin: mark it with @:plugin("<haxelib name>")', local.pos);
		}
		var name = switch meta[0].params[0].expr {
			case EConst(CString(value)): value;
			case _: Context.error('@:plugin takes the haxelib name as a string', meta[0].pos);
		}
		var manifest = manifests.get(name);
		if (manifest == null)
			Context.error('the app does not list the plugin `$name`: add it to `plugins` in hxnme.toml, or select it with -lib', meta[0].pos);
		if (manifest.plugin != path)
			Context.error('${manifest.file} specifies ${manifest.plugin} as the plugin of `$name`, not $path', meta[0].pos);
		for (param in meta[0].params.slice(1))
			switch param.expr {
				case EBinop(OpAssign, {expr: EConst(CIdent("description"))}, value):
					descriptions.set(name, Scheduler.text(value, "description"));
				case _:
					Context.error('@:plugin takes the haxelib name, then `description = "..."`', param.pos);
			}
		for (entry in local.meta.extract(":provides"))
			for (param in entry.params)
				provide(param, name, local);
		var classes = [];
		for (entry in local.meta.extract(":systems"))
			for (param in entry.params)
				classes.push(Scheduler.classOf(param, "@:systems takes the classes that hold the plugin's systems"));
		systems.set(path, classes);
		return null;
	}

	// Records that the plugin `name`, whose class is `local`, provides the
	// service that `expr` refers to. Each service has one provider at most.
	static function provide(expr:Expr, name:String, local:ClassType) {
		var service = switch Context.typeExpr(expr).expr {
			case TTypeExpr(TClassDecl(c)) if (c.get().isInterface): c.get();
			case _: Context.error("@:provides takes the interfaces of the services that the plugin provides", expr.pos);
		}
		var path = service.pack.concat([service.name]).join(".");
		if (!service.meta.has(":service"))
			Context.error('`$path` is not a service: mark the interface with @:service', expr.pos);
		var other = providers.get(path);
		if (other != null && other != name)
			Context.error('`$name` and `$other` both provide `$path`: an app has one provider for each service', expr.pos);
		providers.set(path, name);
	}

	/**
		Checks each plugin class against `hxn.me.Plugin`, and each provider
		against its service. `Plugins.start` calls it first, so it runs when
		the compiler types that body. By then the compiler has built every
		plugin class, and the calls after it are not typed yet.
	**/
	public static function contracts():Expr {
		for (name in order) {
			var manifest = manifests.get(name);
			var c = switch Context.getType(manifest.plugin) {
				case TInst(c, _): c.get();
				case _: Context.error('${manifest.file} specifies ${manifest.plugin} as the plugin class of `$name`, and it is not a class', at(manifest));
			}
			var constructor = c.constructor == null ? null : c.constructor.get();
			var takesNothing = constructor != null && constructor.isPublic && switch Context.follow(constructor.type) {
				case TFun(args, _): Lambda.foreach(args, arg -> arg.opt);
				case _: false;
			};
			if (!takesNothing)
				Context.error('${manifest.plugin} is the plugin class of `$name`: it needs a public constructor that takes no arguments', c.pos);
			conform(c, manifest.plugin, "hxn.me.Plugin", name);
		}
		for (service => name in providers) {
			var path = manifests.get(name).plugin;
			switch Context.getType(path) {
				case TInst(c, _): conform(c.get(), path, service, name);
				case _:
			}
		}
		return macro {};
	}

	// Checks that the class `c` has each method of the interface `service`,
	// with a type that the interface's method accepts.
	static function conform(c:ClassType, path:String, service:String, name:String) {
		var contract = switch Context.getType(service) {
			case TInst(i, _): i.get();
			case _: return;
		}
		for (field in contract.fields.get()) {
			var wanted = TypeTools.toString(field.type);
			var own = TypeTools.findField(c, field.name, false);
			if (own == null || !own.isPublic || !own.kind.match(FMethod(_)))
				Context.error('$path is the plugin class of `$name`, and $service needs the public method `${field.name}`, of type $wanted', c.pos);
			if (!Context.unify(own.type, field.type))
				Context.error('$path.${field.name} has the type ${TypeTools.toString(own.type)}, and $service needs $wanted', own.pos);
		}
	}

	/**
		The expression for the plugin that provides the service `path`, or
		null if no plugin of the app provides it.
	**/
	public static function provider(path:String):Null<Expr> {
		var name = providers.get(path);
		if (name == null)
			return null;
		var field = fields.get(name);
		return macro hxn.me.Plugins.$field;
	}

	/** The description that `@:plugin` gives the plugin `name`, or null. **/
	public static function description(name:String):Null<String>
		return descriptions.get(name);

	/** The plugin classes of the app, in the order they start. **/
	public static function pluginClasses():Array<String>
		return [for (name in order) manifests.get(name).plugin];

	/** The classes that the plugin class `path` lists with `@:systems`. **/
	public static function systemClasses(path:String):Array<String>
		return systems.exists(path) ? systems.get(path) : [];

	static function generate() {
		for (name in names)
			manifests.set(name, read(name));
		var runtime = Context.defined("cppia") ? "cppia" : Context.defined("hl") ? "hl" : Context.defined("cpp") ? "cpp" : null;
		var kind = target();
		for (name in names) {
			var manifest = manifests.get(name);
			for (required in manifest.requires)
				if (!manifests.exists(required))
					Context.error('`$name` requires the plugin `$required`: add it to `plugins` in hxnme.toml, or select it with -lib', at(manifest));
			var runtimes = manifest.platforms.filter(p -> RUNTIMES.contains(p));
			var kinds = manifest.platforms.filter(p -> KINDS.contains(p));
			if ((runtimes.length > 0 && !runtimes.contains(runtime)) || (kinds.length > 0 && !kinds.contains(kind)))
				Context.error('`$name` supports ${manifest.platforms.join(", ")}, and this build is $runtime for $kind', at(manifest));
		}
		order = sorted();
		for (name in order)
			Compiler.addMetadata("@:build(hxn.me.macro.Registry.check())", manifests.get(name).plugin);
		var starts:Array<Expr> = [macro hxn.me.App.checkPlugins()];
		var instances:Array<Field> = [];
		for (name in order) {
			var manifest = manifests.get(name);
			var parts = manifest.plugin.split(".");
			var type:TypePath = {pack: parts.slice(0, -1), name: parts[parts.length - 1]};
			var field = ~/[^A-Za-z0-9_]/g.replace(name, "_");
			if (~/^[0-9]/.match(field) || field == "names" || field == "start" || Lambda.exists(instances, f -> f.name == field))
				field = 'plugin_$field';
			fields.set(name, field);
			instances.push({
				name: field,
				doc: 'The plugin `$name`, after `start` creates it.',
				access: [APublic, AStatic],
				kind: FProp("default", "null", TPath(type)),
				pos: at(manifest),
			});
			var create:Expr = {expr: ENew(type, []), pos: at(manifest)};
			starts.push(macro $i{field} = $create);
			starts.push(macro $i{field}.start());
		}
		var listed = [for (name in order) macro $v{name}];
		var definition = macro class Plugins {
			/** The plugins of the app, in the order they start. **/
			public static final names:Array<String> = $a{listed};

			/** Creates each plugin and starts it, after the plugins it requires. **/
			public static function start():Void
				$b{starts};
		};
		definition.pack = ["hxn", "me"];
		definition.doc = "The plugins of the app, generated by hxnme at compile time.";
		definition.fields = definition.fields.concat(instances);
		Context.defineType(definition);
		Dump.add(definition);
	}

	// The registered plugins, each after the plugins it requires, and in name
	// order where the requirements allow either. Cycles are errors.
	static function sorted():Array<String> {
		var order = [];
		var visiting = [];
		function visit(name:String) {
			if (order.contains(name))
				return;
			if (visiting.contains(name)) {
				var cycle = visiting.slice(visiting.indexOf(name)).concat([name]);
				Context.error('the plugins require each other in a cycle: ${cycle.join(" -> ")}', at(manifests.get(name)));
			}
			visiting.push(name);
			var requires = manifests.get(name).requires.copy();
			requires.sort(Reflect.compare);
			for (required in requires)
				visit(required);
			visiting.pop();
			order.push(name);
		}
		var all = names.copy();
		all.sort(Reflect.compare);
		for (name in all)
			visit(name);
		return order;
	}

	// The kind of platform the build is for.
	static function target():String {
		var triple = Context.definedValue("hxn_triple");
		triple = triple == null ? "" : triple;
		if (Context.defined("wasm") || Context.defined("emscripten") || StringTools.startsWith(triple, "wasm32"))
			return "wasm";
		if (Context.defined("android") || triple.indexOf("android") >= 0)
			return "android";
		if (Context.defined("iphoneos") || Context.defined("iphonesim") || triple.indexOf("apple-ios") >= 0)
			return "ios";
		return "desktop";
	}

	// The manifest of the haxelib `name`, found in one of its class path
	// directories or in the directory above it.
	static function read(name:String):Manifest {
		for (classPath in Context.getClassPath()) {
			var dir = Path.removeTrailingSlashes(classPath == "" ? "." : classPath);
			for (candidate in [dir, Path.directory(dir)]) {
				var file = Path.join([candidate, "haxelib.json"]);
				if (!FileSystem.exists(file))
					continue;
				var info:Dynamic = try Json.parse(File.getContent(file)) catch (_:Dynamic) null;
				if (info == null || info.name != name)
					continue;
				var section:Dynamic = info.hxnme;
				var position = Context.makePosition({file: file, min: 0, max: 0});
				if (section == null || !Std.isOfType(section.plugin, String))
					Context.error('$file has no `hxnme.plugin` that specifies the plugin class of `$name`', position);
				return {
					name: name,
					plugin: section.plugin,
					requires: strings(section.requires, "hxnme.requires", position),
					platforms: strings(section.platforms, "hxnme.platforms", position),
					file: file,
				};
			}
		}
		return Context.error('the plugin `$name` was registered, but no haxelib.json with that name is in its class path, or in the directory above it', Context.currentPos());
	}

	static function strings(value:Dynamic, key:String, position:Position):Array<String> {
		if (value == null)
			return [];
		if (!Std.isOfType(value, Array))
			Context.error('`$key` must be an array of strings', position);
		var out:Array<String> = [];
		for (item in (value : Array<Dynamic>)) {
			if (!Std.isOfType(item, String))
				Context.error('`$key` must be an array of strings', position);
			out.push(item);
		}
		return out;
	}

	static function at(manifest:Manifest):Position {
		return Context.makePosition({file: manifest.file, min: 0, max: 0});
	}
}
#end
