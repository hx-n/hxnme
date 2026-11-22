package hxn.me;

/**
	The phases of a frame, in the order they run. A system names its phase in
	`@:system`, for example `@:system(Update)`. The schedule that hxnme
	generates at compile time has one method for each phase.
**/
enum abstract Phase(Int) {
	/** Runs once, after the plugins start. **/
	var Start;

	/** Runs once for each fixed time step. A frame can run it zero or more times. **/
	var Fixed;

	/** Runs once a frame. **/
	var Update;

	/** Runs once a frame, after `Update`. Its systems record the drawing. **/
	var Render;
}
