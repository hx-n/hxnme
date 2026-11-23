package hxn.me;

/**
	Gives a system read access to a resource. Each resource is the one
	instance of a class that the systems of an app share. `T` must be a class
	whose constructor takes no arguments, and the schedule creates the
	instance. Systems use the fields of `T` directly through `Res<T>`. The
	schedule records that the system reads `T`.
**/
@:forward
abstract Res<T>(T) from T {
	/** The resource itself. **/
	public var value(get, never):T;

	inline function get_value():T
		return this;
}
