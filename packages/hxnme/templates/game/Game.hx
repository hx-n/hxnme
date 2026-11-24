import hxn.me.Asset;
import hxn.me.Assets;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;
import hxn.me.gpu.Camera;
import hxn.me.gpu.Cameras;
import hxn.me.input.Input;
import hxn.me.render2d.Draw;
import hxn.me.render2d.Shadow;
import hxn.me.render2d.Text;
import hxn.me.render2d.Typesetter;
import hxn.text.Font;

/**
	Move the player with WASD, the arrow keys or a gamepad's left stick, and
	collect the gems. R or the gamepad's Start button starts again. The world
	is 960 by 540 units with y up, and a screen camera draws the score over it.
**/
class Game {
	static inline final WIDTH = 960;
	static inline final HEIGHT = 540;
	static inline final SPEED = 320.0;
	static inline final GEMS = 5;
	// How near the player's center must come to a gem's center to collect it.
	static inline final REACH = 26.0;
	// The layer of the score, which the screen camera draws over the world.
	static inline final HUD = 2;
	// Flattened silhouettes on the ground under the player and the gems.
	static final ground = new Shadow(0, -14, 4, 0x000000, 0.45, 0.4);
	static final gemGround = new Shadow(0, -10, 3, 0x000000, 0.35, 0.4);

	static var sheet:Null<Asset<GameAssetsSheetAtlas>>;
	static var font:Null<Asset<Font>>;
	static var label:Null<Text>;
	static var x = WIDTH / 2;
	static var y = HEIGHT / 2;
	static var score = 0;
	// The centers of the gems.
	static final gems:Array<Float> = [];

	@:system(Start)
	static function setup(cameras:ResMut<Cameras>, assets:ResMut<Assets>) {
		var main = cameras.main;
		main.x = WIDTH / 2;
		main.y = HEIGHT / 2;
		var hud = new Camera();
		hud.projection = Screen;
		hud.layers = HUD;
		hud.order = 1;
		cameras.add(hud);
		var store:Assets = assets;
		store.load(GameAssets.Sheet).then(a -> sheet = a);
		store.load(GameAssets.Ui).then(f -> font = f);
		for (_ in 0...GEMS) {
			gems.push(0);
			gems.push(0);
		}
		for (i in 0...GEMS)
			place(i);
	}

	@:system(Update)
	static function play(input:Res<Input<Action>>, time:Res<Time>, typesetter:ResMut<Typesetter>) {
		if (font != null && label == null)
			label = (typesetter : Typesetter).text(font.value, 'Score $score', {size: 24});
		if (input.pressed(Restart))
			setScore(0);
		var dx = clamp(input.value(MoveX)), dy = -clamp(input.value(MoveY));
		var length = Math.sqrt(dx * dx + dy * dy);
		if (length > 1) {
			dx /= length;
			dy /= length;
		}
		x = Math.max(16, Math.min(WIDTH - 16, x + dx * SPEED * time.delta));
		y = Math.max(16, Math.min(HEIGHT - 16, y + dy * SPEED * time.delta));
		for (i in 0...GEMS)
			if (Math.abs(gems[i * 2] - x) < REACH && Math.abs(gems[i * 2 + 1] - y) < REACH) {
				setScore(score + 1);
				place(i);
			}
	}

	// Draws the floor, the gems, the player and the score in each frame, in that order.
	@:system(Update, after = Game.play)
	static function draw(draw:ResMut<Draw>) {
		var d:Draw = draw;
		d.layer = 1;
		d.rect(0, 0, WIDTH, HEIGHT, 0x1B2430);
		if (sheet == null)
			return;
		// The atlas has a property for each region of sheet.json, placed by its center.
		var atlas = sheet.value;
		for (i in 0...GEMS)
			d.region(atlas.gem, gems[i * 2], gems[i * 2 + 1], gemGround);
		d.region(atlas.player, x, y, ground);
		d.layer = HUD;
		d.regionSlice(atlas.panel, 16, 16, 180, 48);
		if (label != null)
			d.text(label, 32, 26, 0xF1F5F9);
	}

	static function setScore(value:Int) {
		score = value;
		if (label != null)
			label.set('Score $score');
	}

	// Moves gem `i` to a random place away from the edges.
	static function place(i:Int) {
		gems[i * 2] = 40 + Math.random() * (WIDTH - 80);
		gems[i * 2 + 1] = 40 + Math.random() * (HEIGHT - 80);
	}

	static function clamp(v:Float):Float
		return v < -1 ? -1 : v > 1 ? 1 : v;
}
