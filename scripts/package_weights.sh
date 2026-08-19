#!/usr/bin/env bash
# Package the See-Through weight set as zstd assets on a GitHub Release.
#
# Why not inside the burrito binary: burrito gzips its payload and gzip is not
# an acceptable archive format here. It also buys ~nothing on safetensors, which
# are already dense, while costing the full 14GB of compression time per build.
# The binary carries the ability to fetch; the weights live here.
#
# Splitting: GitHub caps a single release asset at 2GB. Anything larger is split
# into `.zst.partNN` and reassembled by SeethroughPythonx.Weights, which is the
# same shape seethrough-ggml's fetch-weights.sh already uses.

set -euo pipefail

TAG="${1:?usage: package_weights.sh <tag>}"
REPO="${REPO:-weftspun/interactor-seethrough-pythonx}"
WORK="${WORK:-$(mktemp -d)}"
SPLIT_BYTES="${SPLIT_BYTES:-1900000000}"   # under GitHub's 2GB asset cap

echo "staging into $WORK"

# 1. Pull the weight set from HuggingFace, exactly the repos the pipeline names.
python3 - <<'PY'
import os
from huggingface_hub import snapshot_download
for repo in ["layerdifforg/seethroughv0.0.2_layerdiff3d",
             "24yearsold/seethroughv0.0.1_marigold"]:
    print("snapshot:", repo, flush=True)
    snapshot_download(repo, local_dir=os.path.join(os.environ["WORK"], repo.split("/")[-1]))
PY

cd "$WORK"

# 2. Compress each payload with zstd, and record a hash of the *original*
#    before it is removed. A truncated download that decompresses to a
#    plausible file is the failure this guards: torch loads a corrupt
#    checkpoint far enough to emit garbage rather than to raise.
: > MANIFEST.txt
while IFS= read -r -d '' f; do
  echo "compressing $f"
  sha256sum "$f" >> MANIFEST.txt
  zstd -19 -T0 --rm -q "$f" -o "$f.zst"
done < <(find . -type f \( -name '*.safetensors' -o -name '*.bin' \) -print0)

# 3. Split anything over the asset cap.
while IFS= read -r -d '' z; do
  size=$(stat -c%s "$z")
  if [ "$size" -gt "$SPLIT_BYTES" ]; then
    echo "splitting $z ($size bytes)"
    split -b "$SPLIT_BYTES" -d -a 2 "$z" "$z.part"
    rm -f "$z"
  fi
done < <(find . -type f -name '*.zst' -print0)

# 4. Verify before publishing: every recorded hash must correspond to an asset
#    that exists. A manifest naming files nobody shipped is worse than none.
missing=0
while read -r _hash path; do
  base="${path}"
  if [ ! -f "${base}.zst" ] && ! ls "${base}.zst.part"* >/dev/null 2>&1; then
    echo "MISSING ASSET for $base" >&2
    missing=$((missing + 1))
  fi
done < MANIFEST.txt
if [ "$missing" -ne 0 ]; then
  echo "FAIL: $missing manifest entries have no asset" >&2
  exit 1
fi

# 5. Publish.
mapfile -t assets < <(find . -type f \( -name '*.zst' -o -name '*.zst.part*' \))
echo "publishing ${#assets[@]} assets to $TAG"
gh release create "$TAG" --repo "$REPO" --title "$TAG weights" \
  --notes "zstd-compressed weight set. Reassembled by SeethroughPythonx.Weights." \
  2>/dev/null || echo "release $TAG exists, uploading into it"
gh release upload "$TAG" --repo "$REPO" --clobber "${assets[@]}" MANIFEST.txt

echo "done: $TAG"
