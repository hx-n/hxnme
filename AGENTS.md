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

- Run the checks in the SIMD and scalar builds, on Ash in hybrid, JIT and
  interpreter modes (`ash --mode jit`, `ash --mode interp`).
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
