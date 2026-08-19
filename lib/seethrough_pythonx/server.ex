defmodule SeethroughPythonx.Server do
  @moduledoc """
  Serialises access to the embedded interpreter.

  There is exactly one CPython in this OS process and one GIL over it. This
  GenServer is the queue that makes that explicit: concurrent callers wait
  rather than contending, and the loaded pipeline stays warm between calls.

  `init/1` deliberately does *not* touch Python. Weight loading is minutes of
  work and an Application that blocks its supervisor for minutes on boot is
  indistinguishable from one that has hung. The interpreter is prepared on first
  use instead, and `ready?/0` reports whether that has happened.
  """
  use GenServer

  require Logger

  @call_timeout :timer.minutes(30)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Decompose an image. Blocks until the interpreter is free."
  def run(src, opts \\ []), do: GenServer.call(__MODULE__, {:run, src, opts}, @call_timeout)

  @doc "Environment report, or {:error, reason} if the interpreter is not usable."
  def info, do: GenServer.call(__MODULE__, :info, @call_timeout)

  def ready?, do: GenServer.call(__MODULE__, :ready?)

  @impl true
  def init(_opts), do: {:ok, %{env: nil}}

  @impl true
  def handle_call(:ready?, _from, state), do: {:reply, state.env != nil, state}

  def handle_call(:info, _from, state) do
    case ensure_started(state) do
      {:ok, state} -> {:reply, {:ok, state.env}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:run, src, opts}, _from, state) do
    case ensure_started(state) do
      {:ok, state} -> {:reply, SeethroughPythonx.Pipeline.run(src, opts), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp ensure_started(%{env: env} = state) when env != nil, do: {:ok, state}

  defp ensure_started(state) do
    repo = SeethroughPythonx.torch_repo()
    Logger.info("preparing embedded interpreter against #{repo}")

    case SeethroughPythonx.Pipeline.init(repo) do
      {:ok, env} ->
        Logger.info("torch #{env.torch} / cuda #{env.cuda} on #{env.device}")
        {:ok, %{state | env: env}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
