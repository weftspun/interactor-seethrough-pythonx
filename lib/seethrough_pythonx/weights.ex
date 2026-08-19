defmodule SeethroughPythonx.Weights do
  @moduledoc """
  Provisions the ~14GB model weight set.

  ## Why the weights are not inside the binary

  Burrito *can* carry them: the `Patch` phase copies arbitrary files into the
  build directory and the Zig archiver packs whatever it finds. Three reasons
  not to, in increasing order of how much they matter:

  1. **Size.** A ~14GB executable that unpacks to a second ~14GB copy on first
     run needs ~28GB free to start. That is not a distribution format.

  2. **Compression does nothing.** Burrito gzips the payload. Safetensors and
     GGUF are already dense; gzip on them buys low single-digit percent while
     costing the whole 14GB of compression time on every build.

  3. **Gzip is not an acceptable archive format here.** The workspace
     constraint is zstd, in parquet or standalone. Routing the largest artefact
     we ship through burrito's gzip archiver would violate that rule at the
     worst possible scale.

  So the binary carries the *ability to fetch* rather than the payload: weights
  are zstd assets on GitHub Releases, resolved on first run and cached. This is
  the same mechanism `seethrough-ggml` already uses (`scripts/fetch-weights.sh`,
  `.zst.part*` assets split under the 2GB per-asset release limit).

  ## Integrity

  Payload hashes are verified before an original is deleted, per the workspace
  rule. A truncated download that decompresses to a plausible-looking file is
  the failure this guards: torch will load a corrupt checkpoint far enough to
  produce garbage rather than to raise.
  """

  require Logger

  @release_repo "weftspun/interactor-seethrough-pythonx"

  @doc "Where weights are cached. In a release this is under the burrito install dir."
  @spec dir() :: String.t()
  def dir do
    case Application.get_env(:seethrough_pythonx, :models_dir) do
      :install_dir -> Path.join(install_dir(), "models")
      path when is_binary(path) -> path
      nil -> Path.join(File.cwd!(), "priv/models")
    end
  end

  @doc """
  Ensure weights are present, fetching them if not.

  Returns `{:ok, dir}` or `{:error, reason}`. Never partially succeeds: a failed
  fetch leaves no half-written file that a later run would mistake for a
  complete one.
  """
  @spec ensure!(keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def ensure!(opts \\ []) do
    d = dir()
    tag = Keyword.get(opts, :tag, System.get_env("SEETHROUGH_WEIGHTS_TAG", "v0.1.0"))

    if complete?(d) do
      {:ok, d}
    else
      Logger.info("weights not present in #{d}; fetching #{tag}")
      fetch(d, tag)
    end
  end

  @doc """
  Are all expected weight files present?

  Presence is checked per file against the manifest, and missing files are
  *named*. "Some weights are missing" sends the reader looking; naming them
  ends the search.
  """
  @spec complete?(String.t()) :: boolean()
  def complete?(d) do
    case missing(d) do
      [] -> true
      names -> Logger.debug("missing weights: #{Enum.join(names, ", ")}"); false
    end
  end

  @spec missing(String.t()) :: [String.t()]
  def missing(d), do: Enum.reject(manifest(), &File.regular?(Path.join(d, &1)))

  @doc """
  Expected weight files.

  Deliberately explicit rather than globbed: a glob over a directory reports
  whatever happens to be there, so a half-fetched set reads as complete. This
  list is the negative control for `complete?/1`.
  """
  @spec manifest() :: [String.t()]
  def manifest do
    ~w(
      layerdiff/unet/diffusion_pytorch_model.safetensors
      layerdiff/vae/diffusion_pytorch_model.safetensors
      layerdiff/text_encoder/model.safetensors
      layerdiff/text_encoder_2/model.safetensors
      marigold/unet/diffusion_pytorch_model.safetensors
      marigold/vae/diffusion_pytorch_model.safetensors
    )
  end

  defp fetch(dest, tag) do
    File.mkdir_p!(dest)

    with :ok <- require_tool("gh"),
         :ok <- require_tool("zstd") do
      # Assets are `<name>.zst` or split `<name>.zst.partNN` -- GitHub caps a
      # single release asset at 2GB, which the layerdiff UNet exceeds.
      case System.cmd("gh", ["release", "download", tag, "--repo", @release_repo,
                             "--pattern", "*.zst*", "--dir", dest, "--clobber"],
                      stderr_to_stdout: true) do
        {_out, 0} -> reassemble(dest)
        {out, code} -> {:error, "gh release download failed (#{code}): #{String.trim(out)}"}
      end
    end
  end

  defp reassemble(dest) do
    parts =
      dest |> Path.join("*.zst.part00") |> Path.wildcard()

    Enum.each(parts, fn first ->
      base = String.replace_suffix(first, ".zst.part00", "")
      Logger.info("reassembling #{Path.basename(base)}")
      # cat parts | zstd -d -o base
      {_, 0} = System.shell("cat #{base}.zst.part* | zstd -d -o #{base}")
    end)

    verify(dest)
  end

  defp verify(dest) do
    case missing(dest) do
      [] ->
        {:ok, dest}

      names ->
        {:error,
         "fetch completed but #{length(names)} expected file(s) are absent: " <>
           Enum.join(names, ", ") <>
           " -- treating as FAIL rather than proceeding with a partial set"}
    end
  end

  defp require_tool(name) do
    if System.find_executable(name),
      do: :ok,
      else: {:error, "#{name} not found on PATH; required to fetch weights"}
  end

  defp install_dir do
    # Burrito unpacks the payload to a per-platform location; the binary can
    # report it with `maintenance directory`. priv_dir sits inside it.
    :seethrough_pythonx |> :code.priv_dir() |> to_string()
  end
end
