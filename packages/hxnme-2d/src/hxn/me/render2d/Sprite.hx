package hxn.me.render2d;

/**
	`Sprite` identifies one sprite in `Sprites`. Each handle holds the
	sprite's slot in its low 20 bits and the slot's generation above them, so
	the handle of a removed sprite stays invalid after its slot is used
	again.
**/
abstract Sprite(Int) {
	static inline final SLOT_BITS = 20;
	static inline final SLOT_MASK = (1 << SLOT_BITS) - 1;

	/** `GENERATIONS` sets the largest generation. After it, the generation starts again from 0. **/
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
