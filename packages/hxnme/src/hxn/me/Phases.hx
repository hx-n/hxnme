package hxn.me;

/** The phases of a schedule. The generated `hxn.me.Schedule` implements it. **/
interface Phases {
	function start():Void;
	function fixed():Void;
	function update():Void;
	function render():Void;
}
