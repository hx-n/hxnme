package hxn.me.render2d;

/**
	`Atlas` is a texture with named regions, which `RenderAssets.atlas`
	loads from a JSON file:

	```json
	{
		"image": "sheet.png",
		"pivot": [0.5, 0.5],
		"regions": {
			"hero": {"x": 0, "y": 0, "width": 16, "height": 16},
			"panel": {"x": 16, "y": 0, "width": 12, "height": 12, "slice": [4, 4, 4, 4]}
		}
	}
	```

	When the app declares the atlas as an `AssetRef<Atlas>` field, the asset
	macro reads the file at compile time and gives the atlas a property for
	each region, such as `atlas.panel`, so a wrong name is a compile error.
	`region(name)` finds a region by name at run time.

	`image` is relative to the JSON file. `slice` gives a region's nine-slice
	borders, left, top, right and bottom, in texture pixels. `pivot` gives the
	point that a region is placed and turned by, as a fraction of its width and
	height from its top left: the atlas's `pivot` for every region, which a
	region's own `pivot` replaces. The default is the center. Leave at least
	one pixel between regions, because linear filtering reads the texels next
	to a region at its edges.
**/
@:assetType(hxn.me.render2d.RenderAssets.atlas)
class Atlas {
	public final texture:Texture;

	final regions = new Map<String, Region>();
	// The regions in the order they were added, which `RenderAssets.atlas` makes the order of their names.
	final ordered:Array<Region> = [];

	public function new(texture:Texture)
		this.texture = texture;

	/** Adds `region` under its name. **/
	public function add(region:Region):Void {
		regions.set(region.name, region);
		ordered.push(region);
	}

	/** Returns the region at `index` in the order they were added. The properties of a declared atlas use it. **/
	@:noCompletion public inline function at(index:Int):Region
		return ordered[index];

	/** Returns the region called `name`. It throws if the atlas has none. **/
	public function region(name:String):Region {
		var found = regions.get(name);
		if (found == null)
			throw 'the atlas has no region $name';
		return found;
	}

	/** Returns whether the atlas has a region called `name`. **/
	public function has(name:String):Bool
		return regions.exists(name);

	/** The names of the regions. **/
	public function names():Array<String>
		return [for (name in regions.keys()) name];
}
