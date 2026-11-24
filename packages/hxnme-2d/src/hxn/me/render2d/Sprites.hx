package hxn.me.render2d;

import hxn.text.AtlasKind;
import hxn.text.PreparedText;

import hxn.gpu.Buffer;

/**
	`Sprites` keeps sprites from frame to frame, for example the tiles and
	characters of a scene. `add` returns a handle to the new sprite, and the
	other methods take that handle. The renderer writes one of its sets of
	buffers in each frame, and uploads to that set only the parts of each field
	that changed since it last wrote the set. A change therefore reaches each
	set in turn. Sprites that do not change cost no upload.

	Sprites with the same texture, layer, plane and clip form a group, and each group
	draws with one instanced draw. Groups draw in the order that their first
	sprites were added, and before the contents of `Draw` in the same frame. The
	sprites of one group draw in the order that they were added. `remove`
	changes that order, because it moves the last sprite of the group into the
	place of the removed sprite.
**/
class Sprites {
	/** The layer bits of the sprites added next. Cameras show the layers in their `layers`. **/
	public var layer = 1;

	/** The plane of the sprites added next, or null for the XY plane of the world. **/
	public var plane:Null<Plane>;

	/** The clip of the sprites added next, or null for none. **/
	public var clip:Null<Clip>;

	/** The number of sprites. **/
	public var length(default, null) = 0;

	/** The bytes that the renderer uploaded for sprites in the last frame. **/
	public var uploaded(default, null) = 0;

	@:allow(hxn.me.render2d) final groups:Array<SpriteGroup> = [];

	// The texts in the store, in the order they were added.
	@:allow(hxn.me.render2d) final texts:Array<TextEntry> = [];

	// For each slot: its group, or null when it is free or holds a text, and its index there.
	final slotGroup:Array<Null<SpriteGroup>> = [];
	// For each slot that holds a text: its entry.
	final slotText:Array<Null<TextEntry>> = [];
	final slotIndex:Array<Int> = [];
	final slotGeneration:Array<Int> = [];
	final free:Array<Int> = [];

	public function new() {}

	/**
		Adds `texture` stretched over the rectangle at `x`, `y`, multiplied by
		`color` and `alpha`, and returns its handle. `angle` turns it in radians
		about its center. `u0`, `v0`, `u1`, `v1` select part of the texture,
		from 0 to 1.
	**/
	public function add(texture:Texture, x:Float, y:Float, width:Float, height:Float, color = 0xFFFFFF, alpha = 1.0, angle = 0.0, u0 = 0.0, v0 = 0.0,
			u1 = 1.0, v1 = 1.0):Sprite {
		var group = groupFor(texture);
		var instances = group.instances;
		// Instances start with every field zero, and shape kind 0 is a sprite.
		var i = instances.add();
		instances.set(Instances.RECT, i, x, y, width, height);
		instances.set(Instances.UV, i, u0, v0, u1, v1);
		setTint(instances, i, color, alpha);
		instances.set(Instances.XFORM, i, Math.cos(angle), Math.sin(angle), 0.5, 0.5);
		for (field in 0...Instances.FIELDS)
			group.changed(field, i);
		var slot = take();
		slotGroup[slot] = group;
		slotIndex[slot] = i;
		group.slots[i] = slot;
		return new Sprite(slot, slotGeneration[slot]);
	}

	/**
		Adds `region` of an atlas over the rectangle at `x`, `y`, and returns
		its handle. The rectangle is the region's size in texture pixels unless
		`width` and `height` are given.
	**/
	public function addRegion(region:Region, x:Float, y:Float, ?width:Float, ?height:Float, color = 0xFFFFFF, alpha = 1.0, angle = 0.0):Sprite
		return add(region.texture, x, y, width != null ? width : region.width, height != null ? height : region.height, color, alpha, angle, region.u0,
			region.v0, region.u1, region.v1);

	/**
		Adds `text` in `color` and `alpha`, with the corner of its box that has
		the smaller coordinates at `x`, `y`, and returns its handle. `angle`
		turns it in radians about the center of the box. The store keeps the
		text's glyph instances from frame to frame. It writes and uploads them
		again only after the text moves, turns or changes color, or lays itself
		out again. `move`, `turn`, `tint`, `xOf`, `yOf`, `exists` and `remove`
		take the handle.
	**/
	public function addText(text:Text, x:Float, y:Float, color = 0xFFFFFF, alpha = 1.0, angle = 0.0):Sprite {
		var entry = new TextEntry(text, x, y, color, alpha, angle, layer, plane, clip);
		texts.push(entry);
		var slot = take();
		slotText[slot] = entry;
		return new Sprite(slot, slotGeneration[slot]);
	}

	// Returns a free slot for a new sprite or text.
	function take():Int {
		var slot = free.length > 0 ? free.pop() : slotGroup.length;
		slotGroup[slot] = null;
		slotText[slot] = null;
		if (slotGeneration.length <= slot)
			slotGeneration[slot] = 0;
		length++;
		return slot;
	}

	/** Removes `sprite`. Its handle and every copy of it become invalid. **/
	public function remove(sprite:Sprite):Void {
		var slot = slotOf(sprite);
		var entry = slotText[slot];
		if (entry != null) {
			texts.remove(entry);
			for (group in entry.groups) {
				groups.remove(group);
				for (own in group.buffers)
					for (b in own)
						b.close();
			}
			slotText[slot] = null;
			release(slot);
			return;
		}
		var group = slotGroup[slot];
		var i = slotIndex[slot];
		var last = group.instances.length - 1;
		if (i != last) {
			group.instances.copy(last, i);
			var moved = group.slots[last];
			group.slots[i] = moved;
			slotIndex[moved] = i;
			for (field in 0...Instances.FIELDS)
				group.changed(field, i);
		}
		group.instances.pop();
		group.slots.pop();
		slotGroup[slot] = null;
		release(slot);
	}

	function release(slot:Int):Void {
		slotGeneration[slot] = (slotGeneration[slot] + 1) & Sprite.GENERATIONS;
		free.push(slot);
		length--;
	}

	/** Returns whether `sprite` is still in the store. **/
	public function exists(sprite:Sprite):Bool {
		var slot = sprite.slot;
		return slot < slotGroup.length && (slotGroup[slot] != null || slotText[slot] != null) && slotGeneration[slot] == sprite.generation;
	}

	/** Moves `sprite` so that its corner with the smaller coordinates is at `x`, `y`. **/
	public function move(sprite:Sprite, x:Float, y:Float):Void {
		var entry = textOf(sprite);
		if (entry != null) {
			entry.x = x;
			entry.y = y;
			entry.stale = true;
		} else
			pair(sprite, Instances.RECT, 0, x, y);
	}

	/** Sets the width and height of `sprite`. **/
	public function resize(sprite:Sprite, width:Float, height:Float):Void {
		if (textOf(sprite) != null)
			throw "a text takes its size from its layout";
		pair(sprite, Instances.RECT, 2, width, height);
	}

	/** Turns `sprite` to `angle` radians about its center. **/
	public function turn(sprite:Sprite, angle:Float):Void {
		var entry = textOf(sprite);
		if (entry != null) {
			entry.angle = angle;
			entry.stale = true;
		} else
			pair(sprite, Instances.XFORM, 0, Math.cos(angle), Math.sin(angle));
	}

	/** Sets the color (0xRRGGBB) and alpha that multiply `sprite`'s texture. **/
	public function tint(sprite:Sprite, color:Int, alpha = 1.0):Void {
		var entry = textOf(sprite);
		if (entry != null) {
			entry.color = color;
			entry.alpha = alpha;
			entry.stale = true;
			return;
		}
		var slot = slotOf(sprite);
		var group = slotGroup[slot];
		setTint(group.instances, slotIndex[slot], color, alpha);
		group.changed(Instances.COLOR, slotIndex[slot]);
	}

	/** Selects the part of the texture that `sprite` shows, from 0 to 1. **/
	public function region(sprite:Sprite, u0:Float, v0:Float, u1:Float, v1:Float):Void {
		if (textOf(sprite) != null)
			throw "a text takes its texture coordinates from its atlas";
		var slot = slotOf(sprite);
		var group = slotGroup[slot];
		group.instances.set(Instances.UV, slotIndex[slot], u0, v0, u1, v1);
		group.changed(Instances.UV, slotIndex[slot]);
	}

	/** Returns the x coordinate of `sprite`'s corner with the smaller coordinates. **/
	public function xOf(sprite:Sprite):Float {
		var entry = textOf(sprite);
		if (entry != null)
			return entry.x;
		var slot = slotOf(sprite);
		return slotGroup[slot].instances.get(Instances.RECT, slotIndex[slot], 0);
	}

	/** Returns the y coordinate of `sprite`'s corner with the smaller coordinates. **/
	public function yOf(sprite:Sprite):Float {
		var entry = textOf(sprite);
		if (entry != null)
			return entry.y;
		var slot = slotOf(sprite);
		return slotGroup[slot].instances.get(Instances.RECT, slotIndex[slot], 1);
	}

	function pair(sprite:Sprite, field:Int, at:Int, a:Float, b:Float):Void {
		var slot = slotOf(sprite);
		var group = slotGroup[slot];
		group.instances.setPair(field, slotIndex[slot], at, a, b);
		group.changed(field, slotIndex[slot]);
	}

	// Returns the entry of `sprite` if it is a text, or null if it is a sprite.
	function textOf(sprite:Sprite):Null<TextEntry>
		return slotText[slotOf(sprite)];

	function slotOf(sprite:Sprite):Int {
		if (!exists(sprite))
			throw "the sprite was removed";
		return sprite.slot;
	}

	function groupFor(texture:Texture):SpriteGroup {
		for (group in groups)
			if (group.texture == texture && group.layer == layer && group.plane == plane && group.clip == clip)
				return group;
		var group = new SpriteGroup(texture, layer, plane, clip);
		groups.push(group);
		return group;
	}

	@:allow(hxn.me.render2d) function count(bytes:Int):Void
		uploaded = bytes;

	/** Writes the glyph instances of each text that moved, changed or was laid out again, before the renderer uploads them. **/
	@:allow(hxn.me.render2d) function refresh():Void
		for (entry in texts)
			entry.refresh(groups);

	static inline function setTint(instances:Instances, i:Int, color:Int, alpha:Float):Void
		instances.set(Instances.COLOR, i, ((color >> 16) & 0xFF) / 255, ((color >> 8) & 0xFF) / 255, (color & 0xFF) / 255, alpha);
}

/**
	Each group holds the sprites of one texture, layer, plane and clip, and the
	range of each field that changed since the renderer last uploaded it.
**/
@:allow(hxn.me.render2d)
class SpriteGroup {
	// A text's group follows its atlas, whose texture changes when the atlas grows.
	var texture:Texture;
	final layer:Int;
	final plane:Null<Plane>;
	final clip:Null<Clip>;
	final instances = new Instances(64);

	// The slot of the sprite at each index.
	final slots:Array<Int> = [];

	// For each set of the renderer's buffers and each field, the first index that
	// changed since the renderer last uploaded that set, and one past the last.
	final low = [for (_ in 0...Renderer.SETS) [for (_ in 0...Instances.FIELDS) 0]];
	final high = [for (_ in 0...Renderer.SETS) [for (_ in 0...Instances.FIELDS) 0]];

	// For each set, the vertex buffers of the fields and the number of instances they hold.
	final buffers:Array<Array<Buffer>> = [for (_ in 0...Renderer.SETS) []];
	final capacities = [for (_ in 0...Renderer.SETS) 0];

	function new(texture:Texture, layer:Int, plane:Null<Plane>, clip:Null<Clip>) {
		this.texture = texture;
		this.layer = layer;
		this.plane = plane;
		this.clip = clip;
	}

	// Marks `index` of `field` as changed in every set, so each set uploads it in turn.
	function changed(field:Int, index:Int):Void
		for (set in 0...Renderer.SETS) {
			var low = low[set], high = high[set];
			if (low[field] >= high[field]) {
				low[field] = index;
				high[field] = index + 1;
			} else {
				if (index < low[field])
					low[field] = index;
				if (index >= high[field])
					high[field] = index + 1;
			}
		}

	// Clears the changed ranges of `set` after the renderer uploads it.
	function settle(set:Int):Void
		for (field in 0...Instances.FIELDS)
			low[set][field] = high[set][field] = 0;
}

/**
	Each text entry holds one text of the store, where it is placed, and a
	sprite group of its glyphs for each atlas that they come from.
**/
@:allow(hxn.me.render2d)
private class TextEntry {
	final text:Text;
	var x:Float;
	var y:Float;
	var color:Int;
	var alpha:Float;
	var angle:Float;
	final layer:Int;
	final plane:Null<Plane>;
	final clip:Null<Clip>;

	// The groups of the coverage and color atlases, made when the text first has glyphs in them.
	final groups:Array<SpriteGroup> = [];
	final kinds:Array<AtlasKind> = [];

	// True after a change that the glyph instances do not show yet.
	var stale = true;
	// The layout that the glyph instances show.
	var shown:Null<PreparedText>;

	function new(text:Text, x:Float, y:Float, color:Int, alpha:Float, angle:Float, layer:Int, plane:Null<Plane>, clip:Null<Clip>) {
		this.text = text;
		this.x = x;
		this.y = y;
		this.color = color;
		this.alpha = alpha;
		this.angle = angle;
		this.layer = layer;
		this.plane = plane;
		this.clip = clip;
	}

	// Writes the glyph instances again if the text changed or was laid out again, and keeps each group on its atlas's current texture.
	function refresh(store:Array<SpriteGroup>):Void {
		var laid = text.layout();
		if (stale || laid != shown) {
			stale = false;
			shown = laid;
			for (kind in [AtlasKind.Coverage, AtlasKind.Color]) {
				var k = kinds.indexOf(kind);
				if (k < 0) {
					var atlas = text.atlas(kind);
					if (atlas == null || !uses(laid, kind))
						continue;
					var group = new SpriteGroup(atlas, layer, plane, clip);
					store.push(group);
					groups.push(group);
					kinds.push(kind);
					k = groups.length - 1;
				}
				var group = groups[k];
				group.instances.clear();
				text.write(group.instances, x, y, color, alpha, angle, kind, ignore);
				var n = group.instances.length;
				if (n > 0)
					for (field in 0...Instances.FIELDS) {
						group.changed(field, 0);
						group.changed(field, n - 1);
					}
			}
		}
		for (k in 0...groups.length) {
			var atlas = text.atlas(kinds[k]);
			if (atlas != null)
				groups[k].texture = atlas;
		}
	}

	static function uses(laid:PreparedText, kind:AtlasKind):Bool {
		for (glyph in laid.glyphs)
			if (glyph.kind == kind)
				return true;
		return false;
	}

	static function ignore(_:Texture, _:Int):Void {}
}
