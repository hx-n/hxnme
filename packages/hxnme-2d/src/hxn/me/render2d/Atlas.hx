package hxn.me.render2d;

/**
	`Atlas` is a texture with named regions, which `RenderAssets.atlas`
	loads from a JSON file:

	```json
	{
		"image": "sheet.png",
		"regions": {
			"hero": {"x": 0, "y": 0, "width": 16, "height": 16},
			"panel": {"x": 16, "y": 0, "width": 12, "height": 12, "slice": [4, 4, 4, 4]}
		}
	}
	```

	`image` is relative to the JSON file. `slice` gives a region's nine-slice
	borders, left, top, right and bottom, in texture pixels. Leave at least
	one pixel between regions, because linear filtering reads the texels next
	to a region at its edges.
**/
@:assetType(hxn.me.render2d.RenderAssets.atlas)
class Atlas {
	public final texture:Texture;

	final regions = new Map<String, Region>();

	public function new(texture:Texture)
		this.texture = texture;

	/** Adds `region` under its name. **/
	public function add(region:Region):Void
		regions.set(region.name, region);

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
