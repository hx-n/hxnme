# hxnme

hxnme is an engine framework for developing games and rich interactive apps and experiences, written in Haxe. It is part
of the [hxn](https://github.com/hx-n/hxn) project. The engine consists of a
lightweight kernel and a set of plugins, each published as its own haxelib.
Apps depend on the kernel and add the plugins they need.

## Architecture

```mermaid
flowchart TB
    app["App"]

    subgraph plugins["Plugins"]
        windowing["Window"]
        render["Rendering"]
        audio["Audio"]
        text["Text"]
        input["Input"]
        ecs["ECS"]
        ui["UI"]
        physics["Physics"]
        platform["Platform-specific plugins"]
        custom["Custom plugins"]
    end

    subgraph kernel["Kernel"]
        loop["App loop"]
        scheduler["Frame scheduler"]
        registry["Plugin registry"]
        math["Math"]
        assets["Assets and files"]
    end

    subgraph libraries["hxn libraries"]
        window["hxn-window"]
        gpu["hxn-gpu, hxnsl"]
        av["hxn-av, hxn-audio"]
        textlib["hxn-text"]
        assetlib["hxn-assets, hxn-file"]
    end

    subgraph runtimes["Runtimes"]
        hxcpp["hxcpp"]
        hashlink["HashLink"]
        ash["Ash JIT and AOT"]
    end

    app --> plugins --> kernel --> libraries --> runtimes
```

## Roadmap

1. Core: app loop, input actions, 2D renderer, assets, and `new`, `run` and
   `build` for desktop and web.
2. Physics: a GPU solve, with the CPU solve for deterministic worlds.
3. Dev loop: hot reload of code and assets, on desktop, Android and iOS.
4. Entities: ECS, scenes, prefabs, serialization and audio.
5. UI: layout, widgets, text input and accessibility.
6. 3D: frame graph, meshes, materials and post-processing.
7. Delivery: packaging, signing, and deploys to app stores and the web.

## Agent skills

Each package has an agent skill for coding agents in
[`skills/`](skills/), and the package's haxelib includes it.

## License

Apache-2.0. See [LICENSE](LICENSE).
