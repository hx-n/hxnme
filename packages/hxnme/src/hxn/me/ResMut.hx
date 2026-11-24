package hxn.me;

/**
	`ResMut` gives a system read and write access to a resource. Each
	resource is the one instance of a type that the systems of an app share.
	`T` is a class whose constructor takes no arguments, or an abstract with a
	static `create()`, and the schedule creates the instance. Systems use the
	fields of `T` directly through `ResMut<T>`, and pass it on as a `T`. The
	schedule records that the system writes `T`.
**/
@:forward
abstract ResMut<T>(T) from T to T {}
