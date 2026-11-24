/** `Main` runs three frames in a hidden window. **/
class Main {
	static function main() {
		hxn.me.App.run(Frames);
		Sys.println("hxnme-window: " + hxn.me.Plugins.names.join(", "));
		Sys.println("Window checks passed");
	}
}
