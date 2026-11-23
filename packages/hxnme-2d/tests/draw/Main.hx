/** Runs the 2D check in a hidden window. **/
class Main {
	static function main() {
		hxn.me.App.run(Scene);
		Sys.println("hxnme-2d: " + hxn.me.Plugins.names.join(", "));
		Sys.println("2D checks passed");
	}
}
