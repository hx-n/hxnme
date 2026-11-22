package alpha;

@:plugin("check-alpha")
class AlphaPlugin implements hxn.me.Plugin {
	public function new() {}

	public function start():Void {
		Sys.println("check-alpha started");
	}
}
