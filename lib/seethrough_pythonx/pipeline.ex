defmodule SeethroughPythonx.Pipeline do
  @moduledoc """
  Drives the See-Through decomposition through an embedded CPython interpreter.

  This calls `common/utils/inference_utils.py` directly rather than shelling out
  to `inference/scripts/inference_psd.py`. Shelling out would work and would be
  simpler, but it would also make `pythonx` pointless -- the whole reason to
  embed the interpreter is to hold model state in-process across calls, so the
  ~60s of weight loading is paid once rather than per invocation.

  ## Concurrency

  One decomposition at a time, enforced by `SeethroughPythonx.Server`. The GIL
  makes concurrent evaluation a bottleneck rather than a speedup, and pythonx's
  own docs steer CPU-bound work toward separate OS processes. That guidance is
  about *throughput under concurrency*; for a single sequential decomposition
  the embedded interpreter is not slower, and it keeps the loaded pipeline warm.
  If you need parallel decompositions, run multiple OS processes, not multiple
  Elixir processes against this module.

  ## Settings

  Defaults mirror the ggml/torch comparison recorded in weftspun/logbook#4 so a
  run here is directly comparable: res 1280, 30 steps, seed 42, depth res 768,
  depth steps 4. Depth is passed explicitly -- the two reference implementations
  reach the same depth values through independent default chains that happen to
  agree, which is not the same as being specified.
  """

  @type opts :: [
          res: pos_integer(),
          steps: pos_integer(),
          seed: non_neg_integer(),
          depth_res: pos_integer(),
          depth_steps: pos_integer(),
          save_dir: String.t()
        ]

  @defaults [res: 1280, steps: 30, seed: 42, depth_res: 768, depth_steps: 4]

  @doc "Settings used when none are given. Kept public so callers can record them."
  @spec defaults() :: keyword()
  def defaults, do: @defaults

  @doc """
  Make the reference implementation importable and confirm the GPU is usable.

  The CUDA check is a hard precondition, not a warning. A CUDA-less interpreter
  still runs the pipeline -- on the CPU, several times slower, producing a
  number that looks exactly like a GPU timing. That is the defect recorded in
  weftspun/logbook#4, and it is cheap to refuse up front.
  """
  @spec init(String.t()) :: :ok | {:error, String.t()}
  def init(torch_repo) do
    unless File.dir?(torch_repo) do
      raise ArgumentError, """
      seethrough-torch checkout not found at:
          #{torch_repo}

      Set SEETHROUGH_TORCH_REPO, or configure :seethrough_pythonx, :torch_repo.
      """
    end

    {result, _globals} =
      Pythonx.eval(
        """
        import sys, os, json

        repo = os.fspath(repo_path.decode() if isinstance(repo_path, bytes) else repo_path)
        # `common` holds the packages inference_utils imports as top-level
        # names (`modules.*`, `utils.*`), so it goes on the path, not the root.
        for p in (repo, os.path.join(repo, "common")):
            if p not in sys.path:
                sys.path.insert(0, p)

        import torch
        n = torch.cuda.device_count() if torch.cuda.is_available() else 0
        info = json.dumps({
            "torch": torch.__version__,
            "cuda": torch.version.cuda,
            "device_count": n,
            "device": torch.cuda.get_device_name(0) if n else None,
        })
        info
        """,
        %{"repo_path" => torch_repo}
      )

    info = result |> Pythonx.decode() |> Jason.decode!()

    case info do
      %{"device_count" => 0} ->
        {:error,
         "no usable CUDA device (torch #{info["torch"]}, cuda #{inspect(info["cuda"])}). " <>
           "Refusing to run: a CPU fallback would produce a plausible number that is " <>
           "not a GPU timing."}

      %{"device" => device} ->
        {:ok, %{torch: info["torch"], cuda: info["cuda"], device: device}}
    end
  end

  @doc """
  Decompose `src` into layers and write a layered PSD next to it.

  Returns the number of layers written, which is the cheapest honest signal that
  the run did something: an empty or 1-layer result means the pipeline ran and
  failed to decompose, and that must not read as success.
  """
  @spec run(String.t(), opts()) :: {:ok, map()} | {:error, String.t()}
  def run(src, opts \\ []) do
    o = Keyword.merge(@defaults, opts)
    save_dir = Keyword.get(opts, :save_dir, "workspace/layerdiff_output")

    {result, _globals} =
      Pythonx.eval(
        """
        import json, time
        from utils.inference_utils import apply_layerdiff, apply_marigold

        src = srcp.decode() if isinstance(srcp, bytes) else srcp
        out = save_to.decode() if isinstance(save_to, bytes) else save_to

        t0 = time.perf_counter()
        apply_layerdiff(
            src,
            pretrained=repo_layerdiff.decode(),
            num_inference_steps=steps,
            seed=seed,
            resolution=res,
            save_dir=out,
        )
        t_layerdiff = time.perf_counter() - t0

        t1 = time.perf_counter()
        apply_marigold(
            src,
            pretrained=repo_depth.decode(),
            num_inference_steps=depth_steps,
            seed=seed,
            resolution=depth_res,
            save_dir=out,
        )
        t_marigold = time.perf_counter() - t1

        json.dumps({
            "layerdiff_s": round(t_layerdiff, 3),
            "marigold_s": round(t_marigold, 3),
            "total_s": round(time.perf_counter() - t0, 3),
        })
        """,
        %{
          "srcp" => src,
          "save_to" => save_dir,
          "res" => o[:res],
          "steps" => o[:steps],
          "seed" => o[:seed],
          "depth_res" => o[:depth_res],
          "depth_steps" => o[:depth_steps],
          "repo_layerdiff" => "layerdifforg/seethroughv0.0.2_layerdiff3d",
          "repo_depth" => "24yearsold/seethroughv0.0.1_marigold"
        }
      )

    {:ok, result |> Pythonx.decode() |> Jason.decode!()}
  end
end
