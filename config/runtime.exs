import Config

# SEETHROUGH_TORCH_REPO wins over the compiled-in default, so a burrito binary
# can be pointed at a checkout without rebuilding.
if path = System.get_env("SEETHROUGH_TORCH_REPO") do
  config :seethrough_pythonx, torch_repo: path
end

if models = System.get_env("SEETHROUGH_MODELS") do
  config :seethrough_pythonx, models_dir: models
end
