package hxn.me.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

/**
	The build macro behind `hxn.me.Assets.build()`. It reads the fields of
	type `AssetRef<T>`, gives hxn-assets each one as a dynamic asset, so
	hxn-assets lists and bundles it, and then makes each field an `AssetRef`
	that `Assets.load` takes.

	The asset type of an engine type comes from `@:assetType(expr)` on the
	field, or else on the class of `T`. A type without it is data, which
	hxn-assets decodes as it decodes a dynamic field of that type.
**/
class AssetFields {
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
