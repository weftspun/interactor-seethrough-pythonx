import Config

# Pythonx installs Python and every dependency below into its priv directory at
# *compile* time, via uv. Two consequences worth knowing before editing this:
#
#   1. Changing this block triggers a re-resolve and re-download on next compile.
#   2. Everything here ends up inside the burrito binary. The CUDA torch wheels
#      are ~3GB, which is why `--cpu` variants and the runtime-fetch mode exist
#      (see README, "Why the binary is not self-contained").
#
# The pins mirror seethrough-torch/requirements.txt exactly. They are not
# independent choices: the point of this repo is to run *that* pipeline, and a
# drifting pin makes any comparison against it meaningless. The 2026-08-18
# RunPod incident (weftspun/logbook#4) was caused precisely by an unpinned torch
# resolving to a build whose CUDA was unavailable, which then reported CPU
# timings as GPU timings.
config :pythonx, :uv_init,
  pyproject_toml: """
  [project]
  name = "seethrough_pythonx"
  version = "0.1.0"
  requires-python = "==3.12.*"
  dependencies = [
    "torch==2.8.0",
    "torchvision==0.23.0",
    "numpy==2.2.6",
    "opencv-python==4.13.0.92",
    "pillow==12.1.1",
    "einops==0.8.2",
    "transformers==5.0.0",
    "diffusers==0.37.0",
    "huggingface-hub==1.7.2",
    "accelerate==1.13.0",
    "safetensors==0.7.0",
    "kornia==0.8.2",
    "omegaconf==2.3.0",
    "psd-tools[composite]==1.14.2",
    "scipy==1.15.3",
    "scikit-image==0.25.2",
    "tqdm==4.67.3",
  ]

  # CUDA wheels do not live on PyPI. seethrough-torch documents cu128 to match
  # its pinned torch 2.8.0; keep these in lockstep.
  [[tool.uv.index]]
  name = "pytorch-cu128"
  url = "https://download.pytorch.org/whl/cu128"
  explicit = true

  [tool.uv.sources]
  torch = [{ index = "pytorch-cu128" }]
  torchvision = [{ index = "pytorch-cu128" }]
  """

import_config "#{config_env()}.exs"
