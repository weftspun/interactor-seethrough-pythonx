defmodule SeethroughPythonx.Burrito.StagePython do
  @moduledoc """
  Burrito build step: copy this repo's `python/` tree into the release `priv/`
  so it travels inside the binary.

  Burrito's `Patch` phase is where custom files must land -- it runs after ERTS
  replacement and NIF recompilation, and immediately before the Zig archiver
  packs the build directory. Copying any later means copying into a directory
  that has already been archived, which fails silently: the build succeeds and
  the binary is simply missing the files.

  The Python *sources* are ~8MB and belong in the payload. The model *weights*
  are ~14GB and deliberately do not -- see `SeethroughPythonx.Weights`.
  """

  @behaviour Burrito.Builder.Step

  alias Burrito.Builder.Log
  alias Burrito.Builder.Context

  @impl true
  def execute(%Context{} = context) do
    src = Path.join(File.cwd!(), "python")
    dest = Path.join([context.work_dir, "lib", app_dir(context), "priv", "python"])

    unless File.dir?(src) do
      raise """
      python/ not found at #{src}

      This repo carries the Python sources it runs; without them the binary
      starts and then fails at first decomposition, which is a worse failure
      than not building.
      """
    end

    File.mkdir_p!(dest)
    File.cp_r!(src, dest)

    count = src |> Path.join("**/*") |> Path.wildcard() |> Enum.count(&File.regular?/1)
    Log.success(:step, "staged python/ into priv (#{count} files)")

    context
  end

  # The release lib directory is named `<app>-<version>`; derive it rather than
  # hardcoding, so a version bump does not silently stage into a stale path.
  defp app_dir(%Context{} = context) do
    app = context.mix_release.name
    vsn = context.mix_release.version
    "#{app}-#{vsn}"
  end
end
