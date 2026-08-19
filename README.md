# seethrough-pythonx

See-Through layer decomposition driven from Elixir. Turns a single anime
character illustration into up to 23 inpainted layers plus a depth map.

The model code is **not** reimplemented. This embeds CPython in the BEAM via
[pythonx](https://github.com/livebook-dev/pythonx) and calls the reference
pipeline's `inference_utils` in-process, so output tracks upstream instead of
drifting from it. It ships as a single executable via
[burrito](https://github.com/burrito-elixir/burrito).

```bash
mix deps.get
mix compile      # runs pythonx uv_init: installs Python + ~3GB of CUDA wheels
mix run -e 'SeethroughPythonx.CLI.main()' -- --info
mix run -e 'SeethroughPythonx.CLI.main()' -- -i art.png
```

Defaults are `res 1280`, `steps 30`, `seed 42`, `depth_res 768`, `depth_steps 4`
— matching the ggml/torch comparison in `weftspun/logbook#4`, so runs here are
directly comparable to those numbers.

## Layout

This repo is **rooted here and carries what it runs**. The Python sources live
in `python/` as ordinary tracked files — not a submodule, not a subtree, no
upstream history layered in. One repo, one history, one thing to check out.

```
python/          the pipeline sources this drives (common/, inference/)
lib/             the Elixir wrapper
scripts/         weight packaging
priv/models/     weights, fetched not committed (gitignored)
```

`config/prod.exs` points `:torch_repo` at `{:priv, "python"}`; the burrito build
step `SeethroughPythonx.Burrito.StagePython` copies `python/` into the release
`priv/` so it travels inside the binary. `SEETHROUGH_TORCH_REPO` overrides it at
runtime without a rebuild.

## Weights: zstd on GitHub Releases, not inside the binary

Burrito *can* carry arbitrary files — the `Patch` phase copies them into the
build directory and the Zig archiver packs whatever it finds. The ~8MB of Python
sources go in exactly that way. The ~14GB of weights deliberately do not:

1. **Gzip is not an acceptable archive format here.** Burrito gzips its payload.
   Routing the largest artefact we ship through a gzip archiver would break that
   rule at the worst possible scale.
2. **Compression buys nothing.** Safetensors are already dense. Gzip returns low
   single-digit percent while costing the full 14GB of compression time on every
   build.
3. **Size.** A ~14GB executable that unpacks a second ~14GB copy on first run
   needs ~28GB free just to start.

So the binary carries the *ability to fetch*. `scripts/package_weights.sh`
compresses the set with `zstd -19`, splits anything past GitHub's 2GB asset cap
into `.zst.partNN`, records a `sha256` of each original **before** removing it,
and refuses to publish a manifest naming an asset that does not exist.
`SeethroughPythonx.Weights` reassembles and verifies on first run, and reports a
partial set as a FAIL rather than proceeding.

This is the mechanism `seethrough-ggml` already uses, so the two repos provision
the same way.

## Building

**Burrito does not build on Windows.** Upstream's host/target matrix is explicit:
from a Windows x64 host the Windows x64 target is unsupported — the one build you
would want from a Windows desktop is the one that does not work. Upstream
recommends WSL. `.github/workflows/build.yml` uses Linux for every target,
including Windows.

Zig is pinned to **0.15.2** in CI rather than tracking latest: newer Zig has
broken burrito before, and a build host that follows upstream Zig turns someone
else's release into a failure here.

`pythonx` on Windows is unverified. It loads CPython as a dynamic library and the
docs name `.dll` beside `.so`/`.dylib`, but state no supported-platform list.
Treat Windows `mix run` as unproven until someone records a run.

## One decomposition at a time

There is one CPython in this OS process and one GIL over it.
`SeethroughPythonx.Server` serialises access and keeps the loaded pipeline warm,
so the weight load is paid once rather than per invocation — which is the whole
reason to embed the interpreter instead of shelling out to `inference_psd.py`.

pythonx's docs steer CPU-bound work toward separate OS processes, and that is
correct advice about *throughput under concurrency*: for parallel decompositions,
run several copies of this binary, not several Elixir processes against one. For
a single sequential decomposition the embedding costs nothing and saves a reload.

## Siblings

Three implementations of one pipeline sit on the interactor side:

| repo | implementation | warm median |
|---|---|---|
| `interactor-seethrough-torch` | PyTorch, the reference | 163.7s |
| `interactor-seethrough-ggml` | C++/Vulkan port | 347.3s |
| `interactor-seethrough-pythonx` | this — Elixir driving the reference | not measured |

The torch/ggml figures are one machine (RTX 4090, driver 610.88), one input,
identical settings — see `weftspun/logbook#4`. Because this repo drives the same
Python as `seethrough-torch`, its per-decomposition time should land near 163.7s
once warm, with the embedding cost visible only on the first call. **That is a
hypothesis, not a measurement.** Nothing here has been timed, and it must not be
quoted as though it had.

## Licence

Apache-2.0. Upstream See-Through is Shitagaki Lab, SIGGRAPH 2026.
