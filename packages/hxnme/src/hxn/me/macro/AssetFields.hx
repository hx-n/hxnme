package hxn.me.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.io.Path;
import haxe.macro.Type;

/**
	`AssetFields` implements the build macro of `hxn.me.Assets.build()`. It
	reads the fields of type `AssetRef<T>`, and gives hxn-assets each one as a
	dynamic asset, so that hxn-assets lists and bundles it. Then it makes each
	field an `AssetRef` that `Assets.load` takes.

	The asset type of an engine type comes from `@:assetType(expr)` on the
	field, or else on the class of `T`. Each type without it is data, which
	hxn-assets decodes as it decodes a dynamic field of that type.
**/
class AssetFields {
	// Maps the full name of an engine type to the function that gives each `AssetRef` field of that type a more exact type, such as an atlas with its regions as properties.
	static final refiners = new Map<String, (file:String, owner:ClassType, field:String, pos:Position) -> Null<ComplexType>>();
	// Holds the endings of the names of refined types. Each refined type's name is the declaring class's name, the field's name and one of these endings.
	static final suffixes:Array<String> = [];
	// Holds the refined types that the not-found hook asked for. The hook returns these types instead of defining them.
	static final requested = new Map<String, Null<TypeDefinition>>();

	/**
		Registers `refine` for the engine type called `type`, such as
		`hxn.me.render2d.Atlas`. For each `AssetRef` field of that type,
		`refine` gets the path of the asset's file at compile time, the class
		and the field, and returns the type to use instead, or null to keep the
		engine type. The new type must be an abstract over the engine type,
		named with the class's name, the field's name and `suffix`, such as
		`GameAssetsSheetAtlas`, and defined with `define`. Plugins call it from
		an init macro in their `extraParams.hxml`.
	**/
	public static function refine(type:String, suffix:String, refine:(file:String, owner:ClassType, field:String, pos:Position) -> Null<ComplexType>):Void {
		refiners.set(type, refine);
		if (suffixes.indexOf(suffix) < 0)
			suffixes.push(suffix);
	}

	/**
		Defines `type`, which a refiner made, and returns the type for the
		field to use. It defines the type under its name with `Data` added, and
		makes the original name an alias of it. The field uses the `Data` type,
		because the build macro of the class can run while the compiler looks
		for the alias.
	**/
	public static function define(type:TypeDefinition):ComplexType {
		var name = type.name;
		type.name = name + "Data";
		Context.defineType(type);
		var data = TPath({pack: type.pack, name: type.name});
		var alias:TypeDefinition = {pack: type.pack, name: name, pos: type.pos, doc: type.doc, kind: TDAlias(data), fields: []};
		var full = type.pack.concat([name]).join(".");
		if (requested.exists(full))
			requested.set(full, alias);
		else
			Context.defineType(alias);
		return data;
	}

	/**
		Lets code refer to a refined type, such as `GameAssetsSheetAtlas`,
		before anything builds the class that declares it. When the compiler
		cannot find such a name, the hook builds each class that the name can
		start with, and returns the type that the build macro made. The
		kernel's `extraParams.hxml` calls it.
	**/
	public static function install():Void
		Context.onTypeNotFound(notFound);

	static function notFound(name:String):Null<TypeDefinition> {
		if (requested.exists(name) || !Lambda.exists(suffixes, s -> StringTools.endsWith(name, s)))
			return null;
		var parts = name.split(".");
		var short = parts.pop();
		requested.set(name, null);
		for (i in 1...short.length) {
			var code = short.charCodeAt(i);
			if (code < "A".code || code > "Z".code)
				continue;
			var owner = parts.concat([short.substr(0, i)]).join(".");
			// Reading the statics builds the class, which runs the refiner.
			switch (try Context.getType(owner) catch (_:Dynamic) null) {
				case TInst(c, _): c.get().statics.get();
				case _:
			}
			var made = requested.get(name);
			if (made != null) {
				requested.remove(name);
				return made;
			}
		}
		requested.remove(name);
		return null;
	}

	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var owner = Context.getLocalClass().get();
		var ownerPath = owner.pack.concat([owner.name]).join(".");
		var refs:Array<{name:String, address:String, path:String, inner:ComplexType, type:Expr, pos:Position, access:Array<Access>}> = [];
		for (field in fields) {
			var meta = field.meta == null ? [] : field.meta;
			var asset = find(meta, ":asset");
			if (asset == null)
				continue;
			var declared = switch field.kind {
				case FVar(t, _): t;
				case _: null;
			}
			var inner = declared == null ? null : refParameter(declared, field.pos);
			if (inner == null)
				continue;
			if (find(meta, ":dynamicAsset") == null)
				meta.push({name: ":dynamicAsset", params: [], pos: field.pos});
			var given = find(meta, ":assetType");
			if (given != null) {
				if (given.params.length != 1)
					Context.error("@:assetType takes one asset type", given.pos);
				meta.remove(given);
			}
			var engine = given != null ? given.params[0] : classAssetType(inner, field.pos);
			var type:Expr;
			if (engine != null) {
				// hxn-assets lists and bundles the file as bytes, and the engine type decodes them.
				field.kind = FVar(macro :haxe.io.Bytes, null);
				type = engine;
				var refiner = refiners.get(fullName(inner, field.pos));
				var refined = refiner == null ? null : refiner(Path.join([assetDirectory(), literal(asset.params[asset.params.length - 1])]), owner, field.name,
					field.pos);
				if (refined != null) {
					type = macro(cast $engine : hxn.me.AssetType<$refined>);
					inner = refined;
				}
			} else {
				field.kind = FVar(inner, null);
				var path = literal(asset.params[asset.params.length - 1]);
				var format = find(meta, ":assetFormat");
				var custom = find(meta, ":assetDecode");
				var decode = custom != null ? macro ${custom.params[0]}(bytes) : hxn.assets.macros.Values.decode(macro bytes,
					hxn.assets.macros.Values.kind(inner, path, format == null ? null : literal(format.params[0]), field.pos, true), inner, field.pos);
				type = macro new hxn.me.AssetType<$inner>($v{ownerPath + "." + field.name}, (bytes, _) -> try hxn.Future.resolved(($decode : $inner)) catch (e:haxe.Exception)
					hxn.Future.rejected(e));
			}
			field.meta = meta;
			var address = asset.params.length == 1 ? field.name : literal(asset.params[0]);
			refs.push({name: field.name, address: address, path: literal(asset.params[asset.params.length - 1]), inner: inner, type: type, pos: field.pos,
				access: field.access.copy()});
		}
		fields = hxn.assets.Assets.process(fields);
		if (refs.length == 0)
			return fields;
		var pos = Context.currentPos();
		fields.push({
			name: "__hxnme_catalog",
			access: [APrivate, AStatic],
			kind: FVar(macro :Null<hxn.assets.AssetCatalog>, macro null),
			pos: pos
		});
		fields.push({
			name: "__hxnme_listed",
			access: [APrivate, AStatic],
			kind: FFun({
				args: [],
				ret: macro :hxn.assets.AssetCatalog,
				expr: macro {
					if (__hxnme_catalog == null)
						__hxnme_catalog = catalog();
					return __hxnme_catalog;
				}
			}),
			pos: pos
		});
		for (ref in refs) {
			var field = Lambda.find(fields, f -> f.name == ref.name);
			var inner = ref.inner;
			var access = [for (a in ref.access) if (a != AFinal && a != AInline) a];
			access.push(AFinal);
			field.access = access;
			field.kind = FVar(macro :hxn.me.AssetRef<$inner>, macro new hxn.me.AssetRef<$inner>($v{ref.address}, $v{ref.path}, ${ref.type}, $v{ownerPath}, __hxnme_listed));
		}
		return fields;
	}

	// Returns `T` when `type` is `hxn.me.AssetRef<T>`, or null for any other type.
	static function refParameter(type:ComplexType, pos:Position):Null<ComplexType> {
		return switch (Context.follow(Context.resolveType(type, pos))) {
			case TInst(_.get() => {pack: ["hxn", "me"], name: "AssetRef"}, [inner]): haxe.macro.TypeTools.toComplexType(inner);
			case _: null;
		}
	}

	static function fullName(type:ComplexType, pos:Position):String {
		return switch (Context.follow(Context.resolveType(type, pos))) {
			case TInst(c, _): c.get().pack.concat([c.get().name]).join(".");
			case TAbstract(a, _): a.get().pack.concat([a.get().name]).join(".");
			case _: "";
		}
	}

	// Returns the directory of the app's bundled files, as hxn-assets reads it.
	static function assetDirectory():String {
		var selected = Context.definedValue("hxn_assets_dir");
		return selected == null ? "assets" : selected;
	}

	// Returns the asset type that `@:assetType` on the class or abstract of `type` gives, or null.
	static function classAssetType(type:ComplexType, pos:Position):Null<Expr> {
		var meta = switch (Context.follow(Context.resolveType(type, pos))) {
			case TInst(c, _): c.get().meta;
			case TAbstract(a, _): a.get().meta;
			case _: null;
		}
		if (meta == null || !meta.has(":assetType"))
			return null;
		var entry = meta.extract(":assetType")[0];
		if (entry.params.length != 1)
			Context.error("@:assetType takes one asset type", entry.pos);
		return entry.params[0];
	}

	static function find(meta:Metadata, name:String):Null<MetadataEntry> {
		for (m in meta)
			if (m.name == name)
				return m;
		return null;
	}

	static function literal(e:Expr):String {
		return switch (e.expr) {
			case EConst(CString(s, _)): s;
			case _: Context.error("expected a string literal", e.pos);
		}
	}
}
#end
