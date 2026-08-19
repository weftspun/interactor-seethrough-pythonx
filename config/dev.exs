import Config

# The Python sources live in this repo, at its root. Not a sibling checkout and
# not a subtree: this repo is rooted here and carries what it runs.
config :seethrough_pythonx,
  torch_repo: Path.expand("../python", __DIR__),
  models_dir: Path.expand("../priv/models", __DIR__)
