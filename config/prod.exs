import Config

# In a release the python/ tree is staged into priv/ by the burrito build step
# (SeethroughPythonx.Burrito.StagePython), so it travels inside the binary.
# Weights do not -- see Weights module and README.
config :seethrough_pythonx,
  torch_repo: {:priv, "python"},
  models_dir: :install_dir
