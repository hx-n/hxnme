package hxn.me;

/**
	`Phase` lists the phases of a frame, in the order that they run. Each
	system specifies its phase in `@:system`, for example `@:system(Update)`.
	The schedule that hxnme generates at compile time has one method for each
	phase.
**/
enum abstract Phase(Int) {
	/** Runs once, after the plugins start. **/
	var Start;

	/** Runs once a frame, before `Fixed`. Plugins turn platform events into state here. **/
	var Begin;

	/** Runs once for each fixed time step. One frame can run it zero or more times. **/
	var Fixed;

	/** Runs once a frame. **/
	var Update;

	/** Runs once a frame, after `Update`. Its systems record the drawing. **/
	var Render;
}
