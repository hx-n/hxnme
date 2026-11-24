package hxn.me.render2d;

import hxn.gpu.Buffer;

/**
	`Sprites` keeps sprites from frame to frame, for example the tiles and
	characters of a scene. `add` returns a handle to the new sprite, and the
	other methods take that handle. In each frame, the renderer uploads only the
	part of each field that changed since the last frame. Sprites that do not
	change cost no upload.

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

	// For each slot: its group, or null when it is free, and its index there.
	final slotGroup:Array<Null<SpriteGroup>> = [];
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
		var slot = free.length > 0 ? free.pop() : slotGroup.length;
		slotGroup[slot] = group;
		slotIndex[slot] = i;
		if (slotGeneration.length <= slot)
			slotGeneration[slot] = 0;
		group.slots[i] = slot;
		length++;
		return new Sprite(slot, slotGeneration[slot]);
	}

	/** Removes `sprite`. Its handle and every copy of it become invalid. **/
	public function remove(sprite:Sprite):Void {
		var slot = slotOf(sprite);
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
		slotGeneration[slot] = (slotGeneration[slot] + 1) & Sprite.GENERATIONS;
		free.push(slot);
		length--;
	}

	/** Returns whether `sprite` is still in the store. **/
	public function exists(sprite:Sprite):Bool {
		var slot = sprite.slot;
		return slot < slotGroup.length && slotGroup[slot] != null && slotGeneration[slot] == sprite.generation;
	}

	/** Moves `sprite` so that its corner with the smaller coordinates is at `x`, `y`. **/
	public function move(sprite:Sprite, x:Float, y:Float):Void
		pair(sprite, Instances.RECT, 0, x, y);

	/** Sets the width and height of `sprite`. **/
	public function resize(sprite:Sprite, width:Float, height:Float):Void
		pair(sprite, Instances.RECT, 2, width, height);

	/** Turns `sprite` to `angle` radians about its center. **/
	public function turn(sprite:Sprite, angle:Float):Void
		pair(sprite, Instances.XFORM, 0, Math.cos(angle), Math.sin(angle));

	/** Sets the color (0xRRGGBB) and alpha that multiply `sprite`'s texture. **/
	public function tint(sprite:Sprite, color:Int, alpha = 1.0):Void {
		var slot = slotOf(sprite);
		var group = slotGroup[slot];
		setTint(group.instances, slotIndex[slot], color, alpha);
		group.changed(Instances.COLOR, slotIndex[slot]);
	}

	/** Selects the part of the texture that `sprite` shows, from 0 to 1. **/
	public function region(sprite:Sprite, u0:Float, v0:Float, u1:Float, v1:Float):Void {
		var slot = slotOf(sprite);
		var group = slotGroup[slot];
		group.instances.set(Instances.UV, slotIndex[slot], u0, v0, u1, v1);
		group.changed(Instances.UV, slotIndex[slot]);
	}

	/** Returns the x coordinate of `sprite`'s corner with the smaller coordinates. **/
	public function xOf(sprite:Sprite):Float {
		var slot = slotOf(sprite);
		return slotGroup[slot].instances.get(Instances.RECT, slotIndex[slot], 0);
	}

	/** Returns the y coordinate of `sprite`'s corner with the smaller coordinates. **/
	public function yOf(sprite:Sprite):Float {
		var slot = slotOf(sprite);
		return slotGroup[slot].instances.get(Instances.RECT, slotIndex[slot], 1);
	}

	function pair(sprite:Sprite, field:Int, at:Int, a:Float, b:Float):Void {
		var slot = slotOf(sprite);
		var group = slotGroup[slot];
		group.instances.setPair(field, slotIndex[slot], at, a, b);
		group.changed(field, slotIndex[slot]);
	}

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

	static inline function setTint(instances:Instances, i:Int, color:Int, alpha:Float):Void
		instances.set(Instances.COLOR, i, ((color >> 16) & 0xFF) / 255, ((color >> 8) & 0xFF) / 255, (color & 0xFF) / 255, alpha);
}

/**
	Each group holds the sprites of one texture, layer, plane and clip, and the
	range of each field that changed since the renderer last uploaded it.
**/
@:allow(hxn.me.render2d)
class SpriteGroup {
	final texture:Texture;
	final layer:Int;
	final plane:Null<Plane>;
	final clip:Null<Clip>;
	final instances = new Instances(64);

	// The slot of the sprite at each index.
	final slots:Array<Int> = [];

	// For each field, the first changed index and one past the last.
	final low = [for (_ in 0...Instances.FIELDS) 0];
	final high = [for (_ in 0...Instances.FIELDS) 0];

	// The vertex buffers of the fields, and the number of instances they hold.
	final buffers:Array<Buffer> = [];
	var bufferCapacity = 0;

	function new(texture:Texture, layer:Int, plane:Null<Plane>, clip:Null<Clip>) {
		this.texture = texture;
		this.layer = layer;
		this.plane = plane;
		this.clip = clip;
	}

	inline function changed(field:Int, index:Int):Void {
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

	function settle():Void
		for (field in 0...Instances.FIELDS)
			low[field] = high[field] = 0;
}
