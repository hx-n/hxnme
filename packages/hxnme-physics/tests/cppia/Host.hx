/** Runs a CPPIA script against a host that contains the physics engine. **/
class Host {
	static function main():Void {
		cpp.cppia.Host.runFile(Sys.args()[0]);
	}
}
