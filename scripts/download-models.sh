#!/bin/bash
# Download Magenta RealTime 2 assets from HuggingFace into the default HF cache
# (~/.cache/huggingface). Self-contained — uses huggingface_hub via uv, no
# magenta_rt checkout required. The MagentaRTDemo app and CLIs auto-resolve the
# cached snapshot, so there's nothing to copy or configure afterwards.
#
# Usage: scripts/download-models.sh [model_name]
#        scripts/download-models.sh mrt2_small      # default
#        scripts/download-models.sh mrt2_base
#
# Gated repo? Run `hf auth login` or set HF_TOKEN first.
set -euo pipefail

MODEL="${1:-mrt2_small}"
REPO="google/magenta-realtime-2"

echo "Downloading ${REPO} (resources + ${MODEL}) into the HuggingFace cache…"
uv run --with huggingface_hub python - "$REPO" "$MODEL" <<'PY'
import sys
from huggingface_hub import snapshot_download
repo, model = sys.argv[1], sys.argv[2]
path = snapshot_download(
    repo_id=repo,
    allow_patterns=[
        "resources/musiccoca/*",
        "resources/spectrostream/*",
        f"models/{model}/*",
    ],
)
print("\nSnapshot:", path)
print("Model:    ", f"{path}/models/{model}/{model}.mlxfn")
print("Resources:", f"{path}/resources")
PY
echo "Done. Launch MagentaRTDemo (or run scripts/run.sh) — paths resolve automatically."
