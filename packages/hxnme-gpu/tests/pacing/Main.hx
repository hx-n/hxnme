/** Runs the pacing check in a visible window. **/
class Main {
	static function main() {
		hxn.me.App.run(Pacing);
		Sys.println("hxnme-gpu: " + hxn.me.Plugins.names.join(", "));
		Sys.println("pacing checks passed");
	}
}
