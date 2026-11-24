package hxn.me.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Printer;
import sys.io.File;

/**
	`Dump` writes the classes that hxnme generates to a file when the app
	compiles with `-D hxnme_dump`. The value of the define is the file path.
	If the define has no value, the file is `hxnme-generated.hx`. The file contains each class that
	hxnme generated so far, in the order that hxnme generated them.
**/
class Dump {
	static final definitions:Array<TypeDefinition> = [];

	public static function add(definition:TypeDefinition) {
		if (!Context.defined("hxnme_dump"))
			return;
		definitions.push(definition);
		var out = Context.definedValue("hxnme_dump");
		if (out == null || out == "" || out == "1")
			out = "hxnme-generated.hx";
		var printer = new Printer();
		File.saveContent(out, [for (d in definitions) printer.printTypeDefinition(d)].join("\n\n") + "\n");
	}
}
#end
