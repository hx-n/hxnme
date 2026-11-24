package hxn.me.render2d;

/**
	`Sprite` is the handle of one sprite in `Sprites`. It holds the sprite's
	slot in its low 20 bits and the slot's generation above them, so a handle
	to a removed sprite stays invalid after its slot is used again.
**/
abstract Sprite(Int) {
	static inline final SLOT_BITS = 20;
	static inline final SLOT_MASK = (1 << SLOT_BITS) - 1;

	/** The largest generation before it starts again from 0. **/
	public static inline final GENERATIONS = 0x7FF;

	@:allow(hxn.me.render2d) inline function new(slot:Int, generation:Int)
		this = slot | (generation << SLOT_BITS);

	@:allow(hxn.me.render2d) var slot(get, never):Int;

	inline function get_slot():Int
		return this & SLOT_MASK;

	@:allow(hxn.me.render2d) var generation(get, never):Int;

	inline function get_generation():Int
		return this >>> SLOT_BITS;
}
