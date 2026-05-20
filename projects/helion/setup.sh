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

# ── Torch dependency resolution ──

has_gum() { command -v gum &>/dev/null; }

torch_works() {
    python -c "from torch import Tensor" &>/dev/null
}

local_pytorch_exists() {
    [[ -d "$REPOS/pytorch/torch/__init__.py" ]]
}

install_nightly() {
    echo "==> Installing PyTorch nightly (${HELION_TORCH_INDEX})..."
    # Clean stale editable-install artifacts that shadow the nightly wheel
    rm -rf "$VENV"/lib/python*/site-packages/torch/{_inductor,csrc,share}
    rm -f "$VENV"/lib/python*/site-packages/__editable__*torch*
    rm -rf "$VENV"/lib/python*/site-packages/torch-*.dist-info
    uv pip install --pre "$@" torch triton \
        --index-url "https://download.pytorch.org/whl/${HELION_TORCH_INDEX}" \
        --extra-index-url https://pypi.org/simple
}

install_local() {
    echo "==> Installing PyTorch from local source..."
    rm -rf "$VENV"/lib/python*/site-packages/torch/{_inductor,csrc,share}
    (cd "$REPOS/pytorch" && pip install --no-build-isolation -e .)
}

choose_torch_source() {
    # Prompt only when there's a real choice (local source exists).
    # Returns: "local" or "nightly"
    if ! local_pytorch_exists; then
        echo "nightly"
        return
    fi
    if has_gum && [[ -t 0 ]]; then
        local choice
        choice=$(gum choose --header "Select PyTorch source for Helion:" \
            "local source ($REPOS/pytorch)" \
            "nightly (${HELION_TORCH_INDEX})") || exit 1
        case "$choice" in
            *local*) echo "local" ;;
            *)       echo "nightly" ;;
        esac
    else
        # Non-interactive: prefer local source if it exists
        echo "local"
    fi
}

if [[ "${NIXTORCH_FORCE:-0}" == "1" ]]; then
    # --force: re-evaluate torch source, let user pick
    local_ver=""
    if torch_works; then
        local_ver="$(python -c 'import torch; print(torch.__version__)' 2>/dev/null || true)"
    fi
    source=$(choose_torch_source)
    case "$source" in
        local)   install_local ;;
        nightly) install_nightly --upgrade ;;
    esac
elif torch_works; then
    echo "==> PyTorch already installed ($(python -c 'import torch; print(torch.__version__)'))"
elif local_pytorch_exists; then
    # Torch is broken but local source exists -- offer to fix
    source=$(choose_torch_source)
    case "$source" in
        local)   install_local ;;
        nightly) install_nightly ;;
    esac
else
    install_nightly
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
