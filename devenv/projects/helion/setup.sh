#!/usr/bin/env bash
# Helion workspace setup -- runs once on first container entry
# Config comes from settings.nix via environment variables.
set -euo pipefail

REPOS="${REPOS:-$HOME/workspace}"
WORKSPACE="$REPOS/helion"
VENV="$REPOS/.venv"
MARKER="$REPOS/.helion-setup-done"

if [ -f "$MARKER" ]; then
    exit 0
fi

echo "==> Setting up Helion workspace..."

if [ ! -d "$VENV" ]; then
    echo "==> Creating shared virtual environment..."
    uv venv "$VENV"
fi
source "$VENV/bin/activate"

# Ensure pip is available (uv venv doesn't include it by default)
uv pip install pip 2>/dev/null || true

if [ ! -d "$WORKSPACE" ]; then
    echo "==> Cloning ${HELION_REPO} (${HELION_BRANCH})..."
    git clone --branch "${HELION_BRANCH}" "${HELION_REPO}" "$WORKSPACE"
fi

cd "$WORKSPACE"

# Install torch if not already present (pytorch project builds from source)
if ! python -c "import torch" 2>/dev/null; then
    echo "==> Installing PyTorch from nightly (${HELION_TORCH_INDEX})..."
    uv pip install --pre torch triton \
        --index-url "https://download.pytorch.org/whl/${HELION_TORCH_INDEX}" \
        --extra-index-url https://pypi.org/simple
else
    echo "==> PyTorch already installed ($(python -c 'import torch; print(torch.__version__)'))"
fi

EXTRAS="dev"
if [ -n "${HELION_PIP_EXTRAS:-}" ]; then
    EXTRAS="dev,${HELION_PIP_EXTRAS#[}"
    EXTRAS="${EXTRAS%]}"
fi
echo "==> Installing Helion (editable, extras: $EXTRAS)..."
SETUPTOOLS_SCM_PRETEND_VERSION_FOR_HELION=0.0+dev \
    uv pip install -e ".[$EXTRAS]"

uv pip install pyrefly ruff

touch "$MARKER"
echo "==> Helion workspace ready"
