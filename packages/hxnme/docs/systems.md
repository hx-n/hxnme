# Systems

Systems are static functions with `@:system`. The annotation specifies
the phase of the system, and it can specify the systems that run before or
after it. In this example, `Physics` is a class of systems, and `Bodies` is a
resource class of the app:

```haxe
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;

class Movement {
	@:system(Update, after = Physics, description = "Moves each body by its velocity")
	static function move(time:Res<Time>, bodies:ResMut<Bodies>) {
		for (i in 0...bodies.count)
			bodies.x[i] += bodies.vx[i] * time.delta;
	}
}
```

Each frame runs its phases in this order:

| Phase | Runs |
|---|---|
| `Start` | One time, after the plugins start. |
| `Begin` | One time in each frame, before `Fixed`. Plugins turn the events of the platform into state here, such as the state of the keys. |
| `Fixed` | One time for each fixed step. Each fixed step is a constant interval of time, `app.step` times a second. One frame can run this phase zero or more times. |
| `Update` | One time in each frame. |
| `Render` | One time in each frame, after `Update`. Rendering plugins draw the frame in this phase. |

| Key | Meaning |
|---|---|
| `after`, `before` | One name, or an array of names. Each name is a system (`move`, `Movement.move`) or a class of systems (`Movement`, `game.Movement`). For a class, the constraint applies to each of its systems in the same phase. |
| `description` | What the system does. The kernel records it with the system. |

Systems get their resources as parameters. Each resource is the one
instance of a type that all systems of an app share. The type is a class
with a constructor that takes no arguments, or an abstract with a static
`create()`. The schedule calls `create()` with the resource type as the
expected type, so the abstract can read its type parameters at compile time.
`Res<T>` reads `T`. `ResMut<T>` reads and writes `T`. Both forward the
fields of `T`, and convert to `T`. The kernel records the reads and the
writes of each system from these parameter types, and the dump shows them.

`hxn.me.Events<T>` is a resource that holds a queue of events of type `T`.
Systems with `ResMut<Events<T>>` push events, and systems with
`Res<Events<T>>` read them, for example with a `for` loop. The schedule
clears each queue at the end of the frame, after `Render`. So an event
stays readable until the end of the frame in which a system pushes it.
Order the readers after the writers with `after` or `before`.

The app passes the classes that hold its systems to `App.run`. Each plugin
lists its classes of systems on its plugin class, with
`@:systems(Broadphase, Solver)`. The static functions of the plugin class
can also be systems.

At compile time, the kernel generates the class `hxn.me.Schedule`. Its
constructor creates the resources, and its fields `time`, `lifecycle` and
`display` hold the kernel resources. It has one method for each phase:
`start()`, `fixed()`, `update()` and `render()`. Each method calls every
system of its phase one time, with a direct call. The order obeys every
`after` and `before`. Where no constraint applies, the systems of the
plugins come first, in the order that the plugins start. The systems of the
app come next, in the order that the app passes their classes. The dump also
shows this class, with the reads, the writes and the description of each
system.

Each of these is a compile error that points at the annotation:

- The constraints make a cycle.
- The constraint refers to no system, or to a system in another phase.
- The name matches more than one class or system.
- The phase does not exist.
- The parameter is not a resource.
- The resource type is not a class with a constructor that takes no
  arguments, and not an abstract with a static `create()`.
