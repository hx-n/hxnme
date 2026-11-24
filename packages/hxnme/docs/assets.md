# Assets

The kernel resource `hxn.me.Assets` loads the app's assets with
[hxn-assets](https://github.com/hx-n/hxn-assets). The app declares its assets
on a class built with `@:build(hxn.me.Assets.build())`, as hxn-assets fields:

```haxe
typedef LevelData = {name:String, lives:Int};

@:build(hxn.me.Assets.build())
class GameAssets {
	@:asset("ui/sheet.png") public static var SheetImage:AssetRef<Texture>;
	@:asset("ui/sheet.json") public static var Sheet:AssetRef<Atlas>;
	@:asset("levels/start.json") public static var Start:LevelData;
}
```

The macro runs hxn-assets' macro on the class, which checks each path at
compile time, makes the catalog and bundles the files. Each field of type
`AssetRef<T>` becomes a reference that `assets.load` takes:

```haxe
static var sheet:Null<Asset<Atlas>>;

@:system(Start)
static function setup(assets:ResMut<Assets>) {
	assets.load(GameAssets.Sheet).then(a -> sheet = a);
}
```

The future gives an `Asset` handle, whose `value` is the decoded value. Loads
of one asset share one value. When the app no longer needs the handle, call
`release()`. After the app releases the last handle to it, the kernel
closes the value and unloads its bytes.

The type `T` selects the decoder:

- Each engine type specifies its asset type with `@:assetType(expr)` on its
  class, such as `Texture` and `Atlas` of hxnme-2d. `@:assetType` on the
  field overrides it. Plugins can also give a field a more exact type, such
  as an atlas with a property for each region. The plugin makes that type
  from the file at compile time. It registers a function with
  `hxn.me.macro.AssetFields.refine` from an init macro.
- Any other type is data, which hxn-assets decodes as it decodes a dynamic
  field: `String` from text, `haxe.io.Bytes` as is, and JSON checked against
  the declared type. `@:assetFormat` and `@:assetDecode` apply as in
  hxn-assets.

Fields of other types keep their hxn-assets meaning. hxn-assets decodes
`Start` above at compile time and embeds it, so it needs no load.
hxn-assets bundles only the files that the app's declaration classes list,
so the app declares an atlas's image too.

Each `AssetType` has a name, a `decode` function and an optional `close`
function. `decode` takes the bytes and an `AssetContext`. Through the
context, it loads other files that the value holds, such as the image that an
atlas lists. The context releases them after the value closes:

```haxe
final pair = new AssetType<String>("pair", (bytes, context) ->
	context.load(context.resolve("other.txt"), note).map(other -> bytes.toString() + other));
```

The check in `tests/assets` declares text, JSON and a type with a dependency,
and tests what handles share, close and release.
