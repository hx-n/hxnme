package hxn.me;

/** `Phases` declares the methods that run the phases of a schedule. The generated `hxn.me.Schedule` implements it. **/
interface Phases {
	function start():Void;
	function begin():Void;
	function fixed():Void;
	function update():Void;
	function render():Void;
	function end():Void;
}
