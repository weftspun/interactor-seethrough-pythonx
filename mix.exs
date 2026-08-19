defmodule SeethroughPythonx.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :seethrough_pythonx,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      description:
        "See-Through layer decomposition driven from Elixir, with the PyTorch " <>
          "pipeline embedded in-process via pythonx.",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SeethroughPythonx.Application, []}
    ]
  end

  defp deps do
    [
      # Embeds CPython in the BEAM process. Pinned: pythonx installs Python and
      # the whole dependency set into its priv dir at compile time, so a version
      # bump can silently change which interpreter the pipeline runs under.
      {:pythonx, "~> 0.4.10"},

      # Packages the release as a single self-extracting executable.
      # NOTE: burrito cannot build on Windows -- see README. CI builds on Linux.
      {:burrito, "~> 1.0", runtime: false}
    ]
  end

  defp releases do
    [
      seethrough_pythonx: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            linux: [os: :linux, cpu: :x86_64],
            windows: [os: :windows, cpu: :x86_64],
            macos: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/weftspun/interactor-seethrough-pythonx",
        "Upstream (PyTorch)" => "https://github.com/weftspun/interactor-seethrough-torch"
      }
    ]
  end
end
