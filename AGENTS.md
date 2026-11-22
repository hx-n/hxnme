# Working on hxnme

hxnme is the hxn media engine: a Haxe kernel and first-party plugins, each a
haxelib under `packages/`. Read the [hxn](https://github.com/hx-n/hxn)
conventions first. They apply here too.

## Rules

- Keep the data layout data-oriented. Store components and engine state as
  struct-of-arrays in hxn typed buffers (`hxn.Float32Buffer` and the others),
  so that Rust libraries and the GPU read them without a copy.
- Do the work on the GPU. Use the CPU only where the GPU cannot do the work,
  and document each such case.
- Compose plugins at compile time. Do not look up plugins, systems or
  components by name at run time.
- Do not allocate in a frame. The physics checks measure allocations around
  `World.step`. On Ash, run them with `ASH_GC_TLAB=0`. If it is not set,
  Ash counts allocations only in whole 32 KiB regions, and a check can pass
  when the code allocates. The setting is safe for checks, and it makes programs that
  allocate a lot use more memory.
- Do not write a compound assignment to a `Single` with a `Float` operand,
  such as `s /= f` or `s *= f`. HashLink computes it in single precision, and
  hxcpp computes it in double. Cast the `Single`: `s = (s : Float) / f`.
- Record each third-party dependency of a package in the package's
  `third-party/NOTICES.md`, with its license and notice texts copied
  unchanged under `third-party/licenses/`, in the same commit that adds the
  dependency. The notices ship in the package's haxelib. Code written for
  hxnme needs no entry.
- Keep an agent skill for each package in `skills/<package>/SKILL.md`, and
  update it in the same commit as an API or workflow change. Links in a
  skill are absolute HTTPS URLs. A package's release copies its skill into
  the haxelib's `skills/`.

## Physics

- If a change is not meant to alter the simulation, the physics checks must
  print the same values after it. Compare the output of the checks before
  and after the change.
- Ash performance is the baseline. Run the benchmarks on Ash with
  `--preset game`, the thresholds of a game, before and after a change, on
  the Mac and on the NUC, through `scripts/bench.py`. Compare results only
  with results of the same preset.
- Put measurements in issues. Do not put them in code, comments or commit
  messages.

## Before calling a change done

- Run the checks with `hxn run` in each package's `tests` directory. Install
  `hxn` from the hxn repository with `cargo install --path crates/hxn-cli`.
  The kernel's checks compare every runtime at once:
  `hxn check hl cpp cppia toml-checks.hxml --vm ash`, and in
  `tests/plugins` and `tests/systems`, `hxn check hl cpp cppia app.hxml --vm ash`.
  Those checks use `-lib hxnme`, so run `haxelib dev hxnme packages/hxnme`
  once. `haxe plugin-errors.hxml` and `haxe system-errors.hxml` check the
  compile errors of the registry and the scheduler.
  Each check program has two program files: `<name>.hxml` runs on every
  runtime, and `<name>-simd.hxml` adds the SIMD paths, which run on Ash.
- Run both files on Ash in hybrid, JIT and interpreter modes:
  `hxn run hl checks-simd.hxml --vm "ash --mode jit"`.
- Build both files ahead of time, the build a game ships as, with
  `hxn build hl checks-simd.hxml`, and run the executable it prints.
- Run `<name>.hxml` on hxcpp, CPPIA, and wasm with Ash and with hxcpp, with
  and without threads: `hxn run cpp`, `hxn run cppia`,
  `hxn run hl --wasm --threads`, `hxn run cpp --wasm --threads`. Add
  `--browser` to run it in a web page. hxcpp does not start Haxe threads
  under Emscripten, so `WorkerPool` runs its jobs on the calling thread
  there.
- Compare Ash and hxcpp with
  `hxn check hl cpp <name>.hxml --vm "ash --no-fma"`. It compares the full
  output exactly. Ash fuses multiply-adds by default, and `--no-fma` makes it
  round each operation as HashLink and hxcpp do. `island-parallel-checks`
  prints timings, so it is not compared.
- CPPIA keeps `Single` values in double precision, and the math library of
  wasm differs from the native one. Compare the output of CPPIA and of wasm
  with their own output from before the change.
- Run every runtime that the changed code supports, under a timeout.
- Report each runtime that you did not run.

## Issues and commits

- The issues for hxnme are in the git-bug tracker of the hxn repository,
  under the label `area:me`.
- No planning, backlog or status documents. Put them in issues.
- Commit messages are short. Cite the issue with its full 64-character id in
  a `git-bug:` trailer.
- No AI attribution in commits, issues or pull requests.
- If the user did not ask for a commit or a push, do not make one.
