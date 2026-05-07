#!/usr/bin/env bash
# vLLM workspace setup -- runs once on first container entry
# Config comes from settings.nix via environment variables.
# Follows upstream build-from-source docs:
#   https://docs.vllm.ai/en/latest/getting_started/installation/gpu/index.html
set -euo pipefail

REPOS="${NIXTORCH_WORKSPACE:-$HOME/workspace}"
WORKSPACE="$REPOS/vllm"
VENV="$REPOS/.venv"
MARKER="$REPOS/.vllm-setup-done"

if [ -f "$MARKER" ]; then
    exit 0
fi

echo "==> Setting up vLLM workspace..."

if [ ! -d "$VENV" ]; then
    echo "==> Creating shared virtual environment..."
    uv venv "$VENV"
fi
source "$VENV/bin/activate"

# Ensure pip is available (uv venv doesn't include it by default)
uv pip install pip 2>/dev/null || true

if [ ! -d "$WORKSPACE" ]; then
    echo "==> Cloning ${VLLM_REPO} (${VLLM_BRANCH})..."
    git clone --branch "${VLLM_BRANCH}" "${VLLM_REPO}" "$WORKSPACE"
fi

cd "$WORKSPACE"

# Install torch if not already present (pytorch project builds from source)
if ! python -c "import torch" 2>/dev/null; then
    echo "==> Installing PyTorch from nightly (${VLLM_TORCH_INDEX})..."
    uv pip install --pre torch triton \
        --index-url "https://download.pytorch.org/whl/${VLLM_TORCH_INDEX}" \
        --extra-index-url https://pypi.org/simple
else
    echo "==> PyTorch already installed ($(python -c 'import torch; print(torch.__version__)'))"
fi

# Strip torch from build requirements so the build uses the already-installed
# version (from-source or wheel). This is the upstream-recommended approach
# when building against an existing PyTorch installation.
# See: https://docs.vllm.ai/en/latest/getting_started/installation/gpu/index.html#use-an-existing-pytorch-installation
echo "==> Patching build requirements for existing PyTorch..."
python use_existing_torch.py

# Install build dependencies (torch already removed by the script above)
echo "==> Installing build dependencies..."
uv pip install -r requirements/build/cuda.txt

# Build and install vLLM in editable mode (compiles CUDA kernels)
echo "==> Installing vLLM in editable mode (compiles from source)..."
echo "    MAX_JOBS=${MAX_JOBS:-auto}, TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST:-auto}"
echo "    ccache: $(which ccache 2>/dev/null || echo 'not found')"
uv pip install --no-build-isolation -e .

touch "$MARKER"
echo "==> vLLM workspace ready"
