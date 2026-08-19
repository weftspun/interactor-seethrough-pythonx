import Config

config :seethrough_pythonx,
  torch_repo: Path.expand("../seethrough-torch", __DIR__ |> Path.dirname())
