defmodule SeethroughPythonx.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [SeethroughPythonx.Server]
    Supervisor.start_link(children, strategy: :one_for_one, name: SeethroughPythonx.Supervisor)
  end
end
