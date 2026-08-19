import Config

# Where the Python sources of the reference implementation live. This repo
# drives seethrough-torch's pipeline rather than reimplementing it, so that
# tree has to be importable. Sibling checkout by default -- the workspace
# manifest places both under 3-interactor/.
config :seethrough_pythonx,
  torch_repo: Path.expand("../seethrough-torch", __DIR__ |> Path.dirname())
