# Working on hxnme

hxnme is the hxn media engine. It has a Haxe kernel and first-party plugins,
and each one is a haxelib under `packages/`. Read the
[hxn](https://github.com/hx-n/hxn) conventions first. They apply here too.

## Rules

- Keep the data layout data-oriented. Store components and engine state as
  struct-of-arrays in hxn typed buffers (`hxn.Float32Buffer` and the others),
  so that Rust libraries and the GPU read them without a copy.
- Do the work on the GPU. Use the CPU only where the GPU cannot do the work,
  and document each such case.
- Compose plugins at compile time. Do not look up plugins, systems or
  components by name at run time.
- Do not allocate in a frame. The physics checks measure allocations around
  `World.step`. On Ash, run them with `ASH_GC_TLAB=0`. Without this setting,
  Ash counts allocations only in whole 32 KiB regions, and a check can pass
  when the code allocates. The setting is safe for checks. It makes programs
  that allocate a lot use more memory.
- Do not write a compound assignment to a `Single` with a `Float` operand,
  such as `s /= f` or `s *= f`. HashLink computes it in single precision, and
  hxcpp computes it in double. Cast the `Single`: `s = (s : Float) / f`.
- In the commit that adds a third-party dependency to a package, record the
  dependency in the `third-party/NOTICES.md` of the package. Copy its license
  and notice texts unchanged under `third-party/licenses/`. The notices ship
  in the haxelib of the package. Code written for hxnme needs no entry.
- Keep an agent skill for each package in `skills/<package>/SKILL.md`. When
  you change an API or a workflow, update the skill in the same commit. Each
  link in a skill is an absolute HTTPS URL. The release of each package
  copies its skill into the `skills/` of the haxelib.

## Physics

- If a change is not meant to alter the simulation, the physics checks must
  print the same values after it. Compare the output of the checks before
  and after the change.
- Performance on Ash is the baseline. Before and after a change, run the
  benchmarks on Ash through `scripts/bench.py` with `--preset game`, on the
  Mac and on the NUC. That preset sets the thresholds of a game. Compare
  results only with results of the same preset.
- Put measurements in issues. Do not put them in code, comments or commit
  messages.

## Before calling a change done

- Install `hxn` from the hxn repository with
  `cargo install --path crates/hxn-cli`. Run the checks with `hxn run` in the
  `tests` directory of each package.
  The checks of the kernel compare every runtime at once. Run
  `hxn check hl cpp cppia toml-checks.hxml --vm ash`, and in
  `tests/plugins`, `tests/systems`, `tests/loop` and `tests/headless`, run
  `hxn check hl cpp cppia app.hxml --vm ash`.
  Those checks use `-lib hxnme`, so run `haxelib dev hxnme packages/hxnme`
  once. `haxe plugin-errors.hxml` and `haxe system-errors.hxml` check the
  compile errors of the registry and the scheduler. The check of the window
  plugin, in `packages/hxnme-window/tests/window`, needs a display, and
  `haxelib install hxn-window` run once. The check of the input plugin, in
  `packages/hxnme-input/tests/input`, needs the same. In
  `packages/hxnme-input/tests`, `haxe action-errors.hxml` checks the compile
  errors of action sets.
  Each check program has two program files. `<name>.hxml` runs on every
  runtime, and `<name>-simd.hxml` adds the SIMD paths, which run on Ash.
- Run both files on Ash in hybrid, JIT and interpreter modes, for example
  `hxn run hl checks-simd.hxml --vm "ash --mode jit"`.
- Build both files ahead of time with `hxn build hl checks-simd.hxml`, and
  run the executable that it prints. Games ship in this form.
- Run `<name>.hxml` on hxcpp, CPPIA, and wasm with Ash and with hxcpp, with
  and without threads: `hxn run cpp`, `hxn run cppia`,
  `hxn run hl --wasm --threads`, `hxn run cpp --wasm --threads`. To run it in
  a web page, add `--browser`. hxcpp does not start Haxe threads under
  Emscripten, so `WorkerPool` runs its jobs on the calling thread there.
- Compare Ash and hxcpp with
  `hxn check hl cpp <name>.hxml --vm "ash --no-fma"`. This command compares
  the full output exactly. By default, Ash fuses multiply-adds. With
  `--no-fma`, Ash rounds each operation as HashLink and hxcpp do.
  `island-parallel-checks` prints timings, so leave it out of this
  comparison.
- CPPIA keeps `Single` values in double precision, and the math library of
  wasm differs from the native one. Compare the output of CPPIA and of wasm
  with their own output from before the change.
- Run every runtime that the changed code supports, under a timeout.
- CI runs the checks on macOS, Linux and Windows. `kernel.yml` runs the
  kernel and physics checks, and `plugins.yml` runs the plugin checks and a
  game made with `hxn me new`, on each platform's default GPU driver. A
  change is not known to work on Windows until CI has run it.
- Report each runtime that you did not run.

## Issues and commits

- The issues for hxnme are in the git-bug tracker of the hxn repository,
  under the label `area:me`.
- Do not write planning, backlog or status documents. Put that content in
  issues.
- Keep commit messages short. Cite the issue with its full 64-character id
  in a `git-bug:` trailer.
- Do not put AI attribution in commits, issues or pull requests.
- If the user did not ask for a commit or a push, do not make one.
