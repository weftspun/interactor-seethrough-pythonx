# seethrough-pythonx

See-Through layer decomposition driven from Elixir. Turns a single anime
character illustration into up to 23 inpainted layers plus a depth map.

The model code is **not** reimplemented here. This embeds CPython in the BEAM
via [pythonx](https://github.com/livebook-dev/pythonx) and calls
[`seethrough-torch`](https://github.com/weftspun/interactor-seethrough-torch)'s
own `inference_utils` in-process, so output tracks the reference implementation
instead of drifting from it. It ships as a single executable via
[burrito](https://github.com/burrito-elixir/burrito).

```bash
mix deps.get
mix compile                       # installs Python + deps into pythonx's priv dir
mix run -e 'SeethroughPythonx.CLI.main()' -- --info
mix run -e 'SeethroughPythonx.CLI.main()' -- -i path/to/art.png
```

Defaults are `res 1280`, `steps 30`, `seed 42`, `depth_res 768`, `depth_steps 4`
— matching the ggml/torch comparison in `weftspun/logbook#4`, so runs here are
directly comparable to those numbers.

## Why one process at a time

There is one CPython in this OS process and one GIL over it.
`SeethroughPythonx.Server` serialises access rather than letting callers contend,
and keeps the loaded pipeline warm so the weight load is paid once instead of per
invocation — which is the entire reason to embed the interpreter rather than
shell out to `inference_psd.py`.

pythonx's own documentation steers CPU-bound work toward separate OS processes.
That guidance is about *throughput under concurrency*, and it is correct: if you
want parallel decompositions, run several copies of this binary, not several
Elixir processes against one. For a single sequential decomposition the embedded
interpreter costs nothing and saves the reload.

## Why the binary is not self-contained

Burrito produces a single executable, and this one cannot honestly claim to
carry everything it needs:

| payload | size | where it lives |
|---|---|---|
| Elixir release + ERTS | ~30 MB | inside the binary |
| CUDA torch wheels | ~3 GB | inside the binary (pythonx `priv`) |
| model weights | ~14 GB | **fetched from HuggingFace at first run** |

Weights are deliberately excluded. A 17 GB executable is not a distribution
format, and the weights are already versioned upstream. `HF_HOME` controls where
they are cached; point it at persistent storage or the first run re-downloads.

If the ~3 GB of CUDA wheels is also unacceptable for your distribution, swap the
`[[tool.uv.index]]` block in `config/config.exs` for the CPU wheel index. The
pipeline will then run — slowly, on the CPU — which is a legitimate build for
testing and an illegitimate one for timing.

## Build constraints

**Burrito cannot build on Windows.** Upstream is explicit: use Linux or macOS as
the build machine. Windows is a supported *target*, just not a supported *host*.
`.github/workflows/build.yml` builds all three targets on Linux for this reason.
On a Windows desktop you can still develop and run via `mix run`; you cannot
produce the wrapped binary.

**Zig version is load-bearing.** Burrito documents Zig 0.15.2. Newer Zig has
broken burrito builds before, so CI pins rather than taking whatever is latest.

**pythonx on Windows is unverified here.** It loads CPython as a dynamic library
and the upstream docs name `.dll` alongside `.so`/`.dylib`, but state no
supported-platform list and make no Windows guarantee. Treat Windows `mix run`
as unproven until someone records a run.

## Relationship to the sibling repos

Three implementations of the same pipeline sit on the interactor side:

| repo | implementation | measured |
|---|---|---|
| `interactor-seethrough-torch` | PyTorch, the reference | 163.7s warm |
| `interactor-seethrough-ggml` | C++/Vulkan port | 347.3s warm |
| `interactor-seethrough-pythonx` | this — Elixir driving the reference | not yet |

The torch/ggml numbers are one machine (RTX 4090, driver 610.88), one input,
identical settings; see `weftspun/logbook#4`. This repo drives the same Python
code as `seethrough-torch`, so its per-decomposition time should land near that
163.7s once the interpreter is warm, with the embedding cost visible only on the
first call. That expectation is a hypothesis, not a measurement — nothing here
has been timed yet, and it must not be quoted as though it had.

## Licence

Apache-2.0. The upstream See-Through work is Shitagaki Lab, SIGGRAPH 2026.
