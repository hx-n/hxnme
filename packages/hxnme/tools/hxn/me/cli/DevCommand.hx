package hxn.me.cli;

import hxn.cli.Context;

/**
	Runs an app on Ash with hot reload of its code and assets. On the desktop,
	the running app keeps its state when it can load a change. With web, a
	local server reloads the page after a successful build. A failed build
	leaves the running app or page as it is.
**/
class DevCommand implements hxn.cli.Command {
	/** The program file, or web to run in a browser. **/
	@:arg @:value("web|file.hxml") var file = "app.hxml";

	/** The program file after web. **/
	@:arg @:value("file.hxml") var webFile:Null<String>;

	/** The Ash command, with its options. **/
	@:option @:env("HXN_ASH") @:value("command") var ash = "ash";

	/** The local web server's port. **/
	@:option @:value("port") var port = 8080;

	public function run(context:Context):Int {
		if (file == "web")
			return WebDev.launch(webFile == null ? "app.hxml" : webFile, ash, port, context.cwd, context.root);
		if (webFile != null)
			throw new hxn.cli.Failure("A second program file is supported only after web.");
		if (port != 8080)
			throw new hxn.cli.Failure("--port applies only to hxn me dev web.");
		return Dev.launch(file, ash, context.cwd, context.root);
	}
}
