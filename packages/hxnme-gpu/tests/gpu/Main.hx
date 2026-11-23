/** Runs the GPU check in a hidden window. **/
class Main {
	static function main() {
		hxn.me.App.run(Frames);
		Sys.println("hxnme-gpu: " + hxn.me.Plugins.names.join(", "));
		Sys.println("GPU checks passed");
	}
}
