# hxnme

hxnme is the hxn media engine. It is written in Haxe. It uses the hxn
libraries for windows, the GPU, audio, text, files and assets.

The engine is a small kernel and a set of plugins. Each plugin is a haxelib.
An application lists the plugins it uses, and only those are compiled.

## Packages

| Package | Contents |
|---|---|
| `packages/hxnme` | The kernel. It holds the math types in `hxn.me.math`. |
| `packages/hxnme-physics` | Rigid-body physics in `hxn.me.physics`, with one API for 2D and 3D. |

## Physics

The physics code comes from Chimpmonk, with its checks and its benchmark. It
still uses HashLink types, so it runs only on HashLink and Ash.

Requirements:

- Haxe 4.3.6.
- Ash, or HashLink with the `simd.hdll` of `ash-simd`.
- The `ash-simd` and `hashlink` haxelibs.

To run the checks, go to `packages/hxnme-physics/tests` and run:

```sh
haxe checks.hxml
ash bin/checks.hl
```

`checks-scalar.hxml` builds the same checks without SIMD. The
`island-parallel-checks`, `concurrent-checks` and `world-growth-checks` build
files make the other check programs.

To run the benchmark, go to `packages/hxnme-physics/bench` and run:

```sh
haxe hinged-chain-bench.hxml
../../../scripts/bench.py -- ash bin/hinged-chain-bench.hl 20 on
```

The arguments are the number of chains and the contact mode (`on`, `off` or
`gap`). The program prints one JSON line with the time of each sample, the
best time and the final energy. `scripts/bench.py` runs one benchmark at a
time. If the host is low on memory, it does not start the benchmark. If the
benchmark uses too much memory, output or time, it stops the benchmark.

## License

Apache-2.0. See [LICENSE](LICENSE).
