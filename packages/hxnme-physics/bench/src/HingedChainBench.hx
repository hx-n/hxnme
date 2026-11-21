import hxn.me.physics.core.WorldSnapshot;

/** Replays the same moving chain window for each timing sample. */
class HingedChainBench {
	static function main():Void {
		var args=Sys.args(), count=args.length>0 ? Std.parseInt(args[0]) : 20;
		var mode=args.length>1 ? args[1] : "on";
		if (count==null || count<1 || mode!="on" && mode!="off" && mode!="gap") throw "Use [CHAINS] [on|off|gap]";
		var chain=new HingeChain(true,mode!="off",count,mode=="gap" ? 0.15 : 0.25);
		var w=chain.world;
		for (_ in 0...120) w.step(1.0/60);
		var saved=new WorldSnapshot(); saved.save(w);
		var samples=[];
		for (_ in 0...5) {
			saved.restore(w);
			var start=haxe.Timer.stamp();
			for (_ in 0...30) w.step(1.0/60);
			samples.push((haxe.Timer.stamp()-start)*1000/30);
		}
		var best=Math.POSITIVE_INFINITY;
		for (t in samples) best=Math.min(best,t);
		Sys.println(haxe.Json.stringify({chains:count,mode:mode,samplesMs:samples,bestMs:best,energy:chain.energy()}));
	}
}
