package hxn.me.cli;

import hxn.cli.Context;

/**
	Runs an app on Ash with hot reload of its code and assets. When a file
	changes, the running app gets the change and keeps its state. The app
	restarts after a change that it cannot load, and the command ends when the
	app exits with status 0.
**/
class DevCommand implements hxn.cli.Command {
	/** The program file. **/
	@:arg @:value("file.hxml") var file = "app.hxml";

	/** The Ash command, with its options. **/
	@:option @:env("HXN_ASH") @:value("command") var ash = "ash";

	public function run(context:Context):Int
		return Dev.launch(file, ash, context.cwd, context.root);
}
