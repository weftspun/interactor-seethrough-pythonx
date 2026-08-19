import Config

# In a burrito build there is no sibling checkout: the Python sources are
# staged into priv/ at build time. See mix.exs and the README.
config :seethrough_pythonx,
  torch_repo: {:priv, "seethrough_torch"}
