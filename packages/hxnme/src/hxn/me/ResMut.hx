package hxn.me;

/**
	A resource that a system writes. A resource is the one instance of a class
	that the systems of an app share. `T` must be a class whose constructor
	takes no arguments, and the schedule creates the instance. A system uses
	the fields of `T` directly through `ResMut<T>`. The schedule records that
	the system writes `T`.
**/
@:forward
abstract ResMut<T>(T) from T {
	/** The resource itself. **/
	public var value(get, never):T;

	inline function get_value():T
		return this;
}
