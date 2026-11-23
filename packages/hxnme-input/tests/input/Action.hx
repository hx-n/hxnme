/** The actions of the check. **/
@:actions
enum abstract Action(Int) {
	@:keys(Space) @:buttons(South)
	var Jump;

	@:keyAxis(KeyA, KeyD) @:axis(LeftX)
	var MoveX;

	@:mouse(Left)
	var Fire;

	@:shortcut(Control, KeyS) @:shortcut(Super, KeyS)
	var Save;

	@:shortcut(Control, KeyZ)
	var Undo;

	@:keys(Enter) @:buttons(Confirm)
	var Accept;
}
