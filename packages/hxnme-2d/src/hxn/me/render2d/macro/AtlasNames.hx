package hxn.me.render2d.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import sys.FileSystem;
import sys.io.File;

/**
	`AtlasNames` gives each `AssetRef<Atlas>` field an atlas type with a
	property for each region of its JSON file, which it reads at compile time.
	The properties read the regions by index, in the order of their names, as
	`RenderAssets.atlas` adds them.
**/
class AtlasNames {
	/** Registers the refiner with the kernel's asset macro. hxnme-2d's `extraParams.hxml` calls it. **/
	public static function register():Void
		hxn.me.macro.AssetFields.refine("hxn.me.render2d.Atlas", "Atlas", refine);

	static function refine(file:String, owner:ClassType, field:String, pos:Position):Null<ComplexType> {
		if (!FileSystem.exists(file))
			return null;
		var data:Dynamic = try haxe.Json.parse(File.getContent(file)) catch (e:Dynamic) Context.error('$file is not JSON: $e', pos);
		var names = data.regions == null ? [] : Reflect.fields(data.regions);
		names.sort(Reflect.compare);
		var name = owner.name + field + "Atlas";
		var fields:Array<Field> = [];
		var seen = new Map<String, String>();
		for (i in 0...names.length) {
			var id = identifier(names[i]);
			if (seen.exists(id))
				Context.error('the regions ${seen.get(id)} and ${names[i]} of $file both become the property $id', pos);
			seen.set(id, names[i]);
			fields.push({
				name: id,
				doc: 'The region `${names[i]}`.',
				access: [APublic],
				kind: FProp("get", "never", macro :hxn.me.render2d.Region),
				pos: pos
			});
			fields.push({
				name: "get_" + id,
				access: [AInline],
				kind: FFun({args: [], ret: macro :hxn.me.render2d.Region, expr: macro return this.at($v{i})}),
				pos: pos
			});
		}
		return hxn.me.macro.AssetFields.define({
			pack: owner.pack,
			name: name,
			pos: pos,
			doc: 'The atlas of `${owner.name}.$field`, with a property for each region of its file.',
			meta: [{name: ":forward", params: [], pos: pos}],
			kind: TDAbstract(macro :hxn.me.render2d.Atlas, [AbFrom(macro :hxn.me.render2d.Atlas), AbTo(macro :hxn.me.render2d.Atlas)]),
			fields: fields
		});
	}

	// Returns `name` as a Haxe identifier. Other characters become `_`, and a leading digit gets a `_` before it.
	static function identifier(name:String):String {
		var id = ~/[^A-Za-z0-9_]/g.replace(name, "_");
		return ~/^[0-9]/.match(id) || id == "" ? "_" + id : id;
	}
}
#end
