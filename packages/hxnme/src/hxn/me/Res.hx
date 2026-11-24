package hxn.me;

/**
	`Res` gives a system read access to a resource. Each resource is the one
	instance of a type that the systems of an app share. `T` is a class whose
	constructor takes no arguments, or an abstract with a static `create()`,
	and the schedule creates the instance. Systems use the fields of `T`
	directly through `Res<T>`, and pass it on as a `T`. The schedule records
	that the system reads `T`.
**/
@:forward
abstract Res<T>(T) from T to T {}
