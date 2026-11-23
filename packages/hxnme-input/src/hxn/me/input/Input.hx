package hxn.me.input;

import haxe.macro.Expr;

/**
	The actions of the set `A`, as a resource. `A` is an enum abstract over
	`Int` with `@:actions`, and each of its values is an action. Metadata on
	each value binds it:

	```haxe
	@:actions
	enum abstract Action(Int) {
		@:keys(Space) @:buttons(South)
		var Jump;

		@:keyAxis(KeyA, KeyD) @:axis(LeftX)
		var MoveX;

		@:mouse(Left)
		var Fire;

		@:shortcut(Control, KeyS)
		var Save;
	}
	```

	Systems take `Res<Input<Action>>` and call `input.pressed(Jump)`. The
	schedule creates the resource with `create`, which reads the bindings at
	compile time.
**/
abstract Input<A>(InputState) {
	inline function new(state:InputState)
		this = state;

	/** True in the frame in which `action` went down. **/
	public inline function pressed(action:A):Bool
		return this.isPressed(cast action);

	/** True while `action` is down. **/
	public inline function held(action:A):Bool
		return this.isHeld(cast action);

	/** True in the frame in which `action` came up. **/
	public inline function released(action:A):Bool
		return this.isReleased(cast action);

	/**
		The value of `action`, from -1 to 1. Keys and buttons give 1 while they are down. Gamepad axes give their
		position. Two keys bound with
		`@:keyAxis` give -1 for the first and 1 for the second.
	**/
	public inline function value(action:A):Float
		return this.valueOf(cast action);

	/**
		The label of the first gamepad button bound to `action`, on the family
		of the connected gamepad: "A" on Xbox, "Cross" on PlayStation, "B" on
		Nintendo for `South`. It is empty for an action with no gamepad button.
	**/
	public inline function gamepadLabel(action:A):String
		return this.labelOf(cast action);

	/**
		Returns a signal of whether `action` is down, for code that reacts to changes,
		such as a UI. The plugin creates it the first time it is asked for,
		and sets it once a frame, in `Begin`, when the value changes. Systems
		that run each frame call `held` instead, which costs nothing.
	**/
	public inline function signal(action:A):hxn.Signal<Bool>
		return this.signalOf(cast action);

	/** Creates the resource for the action set of the expected type. The schedule calls it. **/
	public static macro function create():Expr
		return hxn.me.input.macro.Actions.create();
}
