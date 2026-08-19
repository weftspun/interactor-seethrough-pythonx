defmodule SeethroughPythonx do
  @moduledoc """
  See-Through layer decomposition, driven from Elixir.

  Turns a single anime character illustration into up to 23 inpainted layers
  plus a depth map. The model code is not reimplemented here: this drives the
  PyTorch reference in `seethrough-torch` through an embedded CPython
  interpreter, so results track upstream rather than diverging from it.
  """

  @doc "Decompose `src`. See `SeethroughPythonx.Pipeline` for options."
  defdelegate run(src, opts \\ []), to: SeethroughPythonx.Server

  @doc "Report the embedded interpreter's torch/CUDA/device, or an error."
  defdelegate info(), to: SeethroughPythonx.Server

  @doc """
  Resolve where the reference Python sources live.

  In a burrito build there is no sibling checkout, so `{:priv, name}` points at
  a tree staged into the release at build time.
  """
  @spec torch_repo() :: String.t()
  def torch_repo do
    case Application.get_env(:seethrough_pythonx, :torch_repo) do
      {:priv, name} -> :seethrough_pythonx |> :code.priv_dir() |> Path.join(name)
      path when is_binary(path) -> path
      nil -> raise "no :torch_repo configured; set SEETHROUGH_TORCH_REPO"
    end
  end
end
