#!/usr/bin/env bash
# Helion workspace setup -- runs once on first container entry
# Config comes from settings.nix via environment variables.
set -euo pipefail

REPOS="${NIXTORCH_WORKSPACE:-$HOME/workspace}"
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

# Install or upgrade PyTorch from the nightly index.
# When another project (e.g. pytorch) builds torch from source, this is
# skipped entirely.  With --force (NIXTORCH_FORCE=1), an existing pip
# install is upgraded to the latest nightly.
install_torch() {
    uv pip install --pre "$@" torch triton \
        --index-url "https://download.pytorch.org/whl/${HELION_TORCH_INDEX}" \
        --extra-index-url https://pypi.org/simple
}

if ! python -c "import torch" 2>/dev/null; then
    echo "==> Installing PyTorch from nightly (${HELION_TORCH_INDEX})..."
    install_torch
elif [[ "${NIXTORCH_FORCE:-0}" == "1" ]]; then
    echo "==> Upgrading PyTorch to latest nightly (${HELION_TORCH_INDEX})..."
    install_torch --upgrade
else
    echo "==> PyTorch already installed ($(python -c 'import torch; print(torch.__version__)'))"
fi

# Build pip extras string: always include dev, plus any backend extras
# (e.g. HELION_PIP_EXTRAS="[cute-cu12]" -> "dev,cute-cu12").
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
