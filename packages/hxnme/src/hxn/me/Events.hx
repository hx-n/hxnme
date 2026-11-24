package hxn.me;

/**
	`Events` gives systems a queue of events of type `T`, as a resource.
	Systems that take `ResMut<Events<T>>` push events, and systems that take
	`Res<Events<T>>` read them. The schedule clears each queue at the end of
	the frame, after `Render`. So an event stays readable until the end of
	the frame in which a system pushes it. Order the readers after the
	writers with `after` or `before`.
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

	/** Returns the event at `index`, from 0. **/
	public inline function get(index:Int):T
		return items[index];

	/** Returns an iterator over the events, in the order that systems pushed them. **/
	public inline function iterator():Iterator<T>
		return items.iterator();

	/** Removes every event. The schedule calls it at the end of each frame. **/
	public function clear():Void
		items.resize(0);
}
