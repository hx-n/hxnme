package beta;

@:plugin("check-beta")
class BetaPlugin implements hxn.me.Plugin {
	public function new() {}

	public function start():Void {
		Sys.println("check-beta started");
	}
}
