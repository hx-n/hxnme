package hxn.me;

/**
	Gives systems a queue of events of type `T`, as a resource. Systems that
	take `ResMut<Events<T>>` push events, and systems that take
	`Res<Events<T>>` read them. The schedule clears each queue at the end of
	the frame, after `Render`, so an event is readable for the rest of the
	frame in which it is pushed. Order the readers after the writers with
	`after` or `before`.
**/
class Events<T> {
	final items:Array<T> = [];

	public function new() {}

	/** The number of events in the queue. **/
	public var length(get, never):Int;

	inline function get_length():Int
		return items.length;

	/** Adds `event` at the end of the queue. **/
	public inline function push(event:T):Void
		items.push(event);

	/** The event at `index`, from 0. **/
	public inline function get(index:Int):T
		return items[index];

	/** The events in the order they were pushed. **/
	public inline function iterator():Iterator<T>
		return items.iterator();

	/** Removes every event. The schedule calls it at the end of each frame. **/
	public function clear():Void
		items.resize(0);
}
