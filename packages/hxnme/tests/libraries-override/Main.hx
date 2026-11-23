/** Prints which of check-picker's target libraries the build hook added. **/
class Main {
	static function main() {
		hxn.me.Plugins.start();
		Sys.println("target library: " + Picked.NAME);
	}
}
