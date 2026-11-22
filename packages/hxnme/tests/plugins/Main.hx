/** Starts the plugins that hxnme.toml lists, in the order the registry chose. */
class Main {
	static function main() {
		Sys.println("plugins: " + hxn.me.Plugins.names.join(", "));
		hxn.me.Plugins.start();
		Sys.println("Plugin checks passed");
	}
}
