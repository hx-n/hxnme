/** The game's actions. A gamepad's stick gives -1 for up, so the keys for up give -1 too. **/
@:actions
enum abstract Action(Int) {
	@:keyAxis(KeyA, KeyD) @:keyAxis(ArrowLeft, ArrowRight) @:axis(LeftX)
	var MoveX;

	@:keyAxis(KeyW, KeyS) @:keyAxis(ArrowUp, ArrowDown) @:axis(LeftY)
	var MoveY;

	@:keys(KeyR) @:buttons(Start)
	var Restart;
}
