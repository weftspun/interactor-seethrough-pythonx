defmodule SeethroughPythonx.CLI do
  @moduledoc """
  Burrito entry point.

  Burrito passes argv through `Burrito.Util.Args.argv/0` rather than
  `System.argv/0`; the latter is empty in a wrapped binary, which is a
  confusing way to discover the difference.
  """

  alias SeethroughPythonx.Pipeline

  def main do
    args =
      if function_exported?(Burrito.Util.Args, :argv, 0) do
        apply(Burrito.Util.Args, :argv, [])
      else
        System.argv()
      end

    args |> parse() |> dispatch()
  end

  defp parse(argv) do
    {opts, rest, invalid} =
      OptionParser.parse(argv,
        strict: [
          input: :string,
          out: :string,
          res: :integer,
          steps: :integer,
          seed: :integer,
          depth_res: :integer,
          depth_steps: :integer,
          help: :boolean,
          info: :boolean
        ],
        aliases: [i: :input, o: :out, h: :help]
      )

    %{opts: opts, rest: rest, invalid: invalid}
  end

  defp dispatch(%{invalid: [_ | _] = invalid}) do
    # An unknown flag is an error, not something to ignore. Silently dropping
    # `--setps 30` would run at the default and report a number as though the
    # requested setting had been applied.
    for {flag, _} <- invalid, do: IO.puts(:stderr, "unknown or malformed option: #{flag}")
    usage()
    System.halt(2)
  end

  defp dispatch(%{opts: opts}) do
    cond do
      opts[:help] -> usage()
      opts[:info] -> show_info()
      opts[:input] -> run(opts)
      true -> usage() && System.halt(2)
    end
  end

  defp show_info do
    case SeethroughPythonx.info() do
      {:ok, env} ->
        IO.puts("torch      #{env.torch}")
        IO.puts("cuda       #{env.cuda}")
        IO.puts("device     #{env.device}")
        IO.puts("torch_repo #{SeethroughPythonx.torch_repo()}")

      {:error, reason} ->
        IO.puts(:stderr, "FAIL: #{reason}")
        System.halt(1)
    end
  end

  defp run(opts) do
    src = opts[:input]

    unless File.exists?(src) do
      IO.puts(:stderr, "FAIL: input not found: #{src}")
      System.halt(1)
    end

    settings = Keyword.take(opts, [:res, :steps, :seed, :depth_res, :depth_steps])
    effective = Keyword.merge(Pipeline.defaults(), settings)

    IO.puts(
      "res #{effective[:res]}  steps #{effective[:steps]}  seed #{effective[:seed]}  " <>
        "depth_res #{effective[:depth_res]}  depth_steps #{effective[:depth_steps]}"
    )

    settings = if out = opts[:out], do: Keyword.put(settings, :save_dir, out), else: settings

    case SeethroughPythonx.run(src, settings) do
      {:ok, timings} ->
        IO.puts(
          "layerdiff #{timings["layerdiff_s"]}s  marigold #{timings["marigold_s"]}s  " <>
            "total #{timings["total_s"]}s"
        )

      {:error, reason} ->
        IO.puts(:stderr, "FAIL: #{reason}")
        System.halt(1)
    end
  end

  defp usage do
    IO.puts("""
    seethrough_pythonx -i <image> [options]

      -i, --input PATH     input illustration (png/jpg)
      -o, --out DIR        output directory (default workspace/layerdiff_output)
          --res N          layerdiff resolution (default 1280)
          --steps N        layerdiff steps (default 30)
          --seed N         seed (default 42)
          --depth-res N    depth resolution (default 768)
          --depth-steps N  depth steps (default 4)
          --info           report torch/CUDA/device and exit
      -h, --help           this message

    Defaults match the settings used for the ggml-vs-torch comparison in
    weftspun/logbook#4, so runs here are directly comparable to those.
    """)
  end
end
