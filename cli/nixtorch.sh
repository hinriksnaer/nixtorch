# nixtorch -- CLI for managing the nixtorch development environment.
# Must be run inside the nix develop shell.
#
# Build logic lives in projects/<name>/setup.sh -- this CLI
# just orchestrates them in the correct order.

REPOS="${NIXTORCH_WORKSPACE:-$HOME/workspace}"
VENV="$REPOS/.venv"

# ── Guard: refuse to run outside the dev shell ──
if [[ -z "${NIXTORCH_ENABLED_PROJECTS:-}" && -z "${CUDA_HOME:-}" ]]; then
  echo "error: nixtorch must be run inside the nix develop shell." >&2
  echo "  run: nix develop github:hinriksnaer/nixtorch" >&2
  exit 1
fi

# ── Helpers ──
info()  { echo ":: $*"; }
warn()  { echo "!! $*" >&2; }
error() { echo "error: $*" >&2; exit 1; }

has_gum() { command -v gum &>/dev/null; }

get_repo()   { local v="${1^^}_REPO";   echo "${!v:-}"; }
get_branch() { local v="${1^^}_BRANCH"; echo "${!v:-}"; }

fmt_duration() {
  local secs=$1
  if (( secs >= 3600 )); then
    printf "%dh%02dm%02ds" $((secs/3600)) $((secs%3600/60)) $((secs%60))
  elif (( secs >= 60 )); then
    printf "%dm%02ds" $((secs/60)) $((secs%60))
  else
    printf "%ds" "$secs"
  fi
}

enabled_projects() {
  echo "${NIXTORCH_ENABLED_PROJECTS:-}" | tr ' ' '\n' | grep -v '^$'
}

resolve_projects() {
  # If specific projects given, validate and return in build order.
  # Otherwise return all enabled (already in build order from Nix).
  if [[ $# -gt 0 ]]; then
    local ordered=""
    for p in $(enabled_projects); do
      for req in "$@"; do
        if [[ "$p" == "$req" ]]; then
          ordered+="$p"$'\n'
        fi
      done
    done
    # Validate all requested projects were found
    for req in "$@"; do
      if ! echo "$ordered" | grep -qx "$req"; then
        error "project '$req' is not enabled. Enabled: ${NIXTORCH_ENABLED_PROJECTS:-none}"
      fi
    done
    echo "$ordered" | grep -v '^$'
  else
    enabled_projects
  fi
}

choose_project() {
  local header="${1:-Select a project:}"
  if has_gum && [[ -t 0 ]]; then
    gum choose --header "$header" $(enabled_projects) || exit 0
  else
    return 1
  fi
}

# ── Reinstall logic (shared by build and standalone) ──

reinstall_project() {
  local project=$1
  local dir="$REPOS/$project"

  if [[ ! -d "$dir" ]]; then
    warn "$project: not cloned, skipping (run 'nixtorch build $project' first)"
    return 1
  fi

  case "$project" in
    pytorch)
      info "$project: cleaning stale site-packages"
      rm -rf "$VENV"/lib/python*/site-packages/torch/{_inductor,csrc,share}
      info "$project: re-registering editable install"
      (cd "$dir" && pip install --no-build-isolation -e .)
      ;;
    helion)
      local EXTRAS="dev"
      if [ -n "${HELION_PIP_EXTRAS:-}" ]; then
        EXTRAS="dev,${HELION_PIP_EXTRAS#[}"
        EXTRAS="${EXTRAS%]}"
      fi
      info "$project: re-registering editable install (extras: $EXTRAS)"
      (cd "$dir" && SETUPTOOLS_SCM_PRETEND_VERSION_FOR_HELION=0.0+dev \
        uv pip install -e ".[$EXTRAS]")
      ;;
    vllm)
      info "$project: re-registering editable install"
      (cd "$dir" && uv pip install --no-build-isolation -e .)
      ;;
    *)
      warn "$project: reinstall not supported"
      return 1
      ;;
  esac
}

# ── Commands ──

cmd_build() {
  local force=0 update=0
  local args=()

  for arg in "$@"; do
    case "$arg" in
      --force|-f) force=1 ;;
      --update|-u) update=1 ;;
      *) args+=("$arg") ;;
    esac
  done

  # No projects specified -- prompt with gum or build all enabled
  if [[ ${#args[@]} -eq 0 ]]; then
    local selected
    if selected=$(choose_project "Select a project to build:"); then
      args=("$selected")
    fi
  fi

  local projects
  projects=$(resolve_projects "${args[@]+"${args[@]}"}")

  for project in $projects; do
    local setup="$NIXTORCH_ROOT/projects/${project}/setup.sh"
    local marker="$REPOS/.${project}-setup-done"
    local dir="$REPOS/$project"

    if [[ ! -f "$setup" ]]; then
      error "$project: no setup script found at $setup"
    fi

    # --update: pull latest before building
    if [[ $update -eq 1 && -d "$dir/.git" ]]; then
      local branch
      branch=$(get_branch "$project")
      info "$project: pulling latest ($branch)"
      git -C "$dir" fetch origin
      git -C "$dir" checkout "$branch"
      git -C "$dir" pull --ff-only
      git -C "$dir" submodule update --init --recursive
    fi

    # --force: confirm then remove marker so setup.sh re-runs full build
    if [[ $force -eq 1 && -f "$marker" ]]; then
      if has_gum && [[ -t 0 ]]; then
        gum confirm "Force rebuild $project? This clears the build marker." || continue
      fi
      info "$project: clearing build marker"
      rm -f "$marker"
    fi

    if [[ -f "$marker" ]]; then
      # Already built -- just re-register the editable install
      info "$project: already built, re-registering editable install"
      local start=$SECONDS
      reinstall_project "$project"
      local elapsed=$(( SECONDS - start ))
      info "$project: done ($(fmt_duration $elapsed))"
    else
      # Not built -- run full setup
      info "$project: running setup"
      local start=$SECONDS
      NIXTORCH_FORCE=$force bash "$setup"
      local elapsed=$(( SECONDS - start ))
      info "$project: done ($(fmt_duration $elapsed))"
    fi
  done
}

cmd_status() {
  local all_projects="pytorch helion vllm"

  # ── Environment info ──
  echo "Environment:"
  printf "  %-18s %s\n" "CUDA toolkit:" "${CUDA_HOME:-not set}"
  printf "  %-18s %s\n" "CUDA devices:" "${CUDA_VISIBLE_DEVICES:-all}"

  local nvcc_ver
  nvcc_ver=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9.]+' || echo "not found")
  printf "  %-18s %s\n" "nvcc:" "$nvcc_ver"

  local python_ver
  python_ver=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "not found")
  printf "  %-18s %s\n" "Python:" "$python_ver"

  local torch_ver
  torch_ver=$(python3 -c "import torch; print(f'{torch.__version__} (CUDA {torch.version.cuda})')" 2>/dev/null || echo "not installed")
  printf "  %-18s %s\n" "torch:" "$torch_ver"

  local ccache_hit
  ccache_hit=$(ccache -s 2>/dev/null | grep -i 'hit rate' | head -1 | sed 's/.*hit rate/hit rate/' || echo "not available")
  printf "  %-18s %s\n" "ccache:" "$ccache_hit"
  echo ""

  # ── Project table ──
  printf "%-12s %-8s %-8s %-10s %s\n" "PROJECT" "ENABLED" "BUILT" "BRANCH" "REPO"
  printf "%-12s %-8s %-8s %-10s %s\n" "-------" "-------" "-----" "------" "----"

  for project in $all_projects; do
    local enabled="no" built="no" branch repo dir marker
    repo=$(get_repo "$project")
    branch=$(get_branch "$project")
    dir="$REPOS/$project"
    marker="$REPOS/.${project}-setup-done"

    if enabled_projects | grep -qx "$project" 2>/dev/null; then
      enabled="yes"
    fi
    if [[ -f "$marker" ]]; then
      built="yes"
      branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "$branch")
    elif [[ -d "$dir/.git" ]]; then
      built="cloned"
      branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "$branch")
    fi

    printf "%-12s %-8s %-8s %-10s %s\n" "$project" "$enabled" "$built" "${branch:-—}" "${repo:-—}"
  done

  echo ""
  if [[ -d "$VENV" ]]; then
    info "venv: $VENV"
  else
    info "venv: not created (run 'nixtorch build')"
  fi
}

cmd_clean() {
  local args=()
  for arg in "$@"; do
    args+=("$arg")
  done

  # Full clean (no specific projects) -- confirm first
  if [[ ${#args[@]} -eq 0 ]]; then
    if has_gum && [[ -t 0 ]]; then
      gum confirm "Remove all project repos, build markers, and shared venv?" || exit 0
    fi
  fi

  local projects
  projects=$(resolve_projects "${args[@]+"${args[@]}"}")

  for project in $projects; do
    local dir="$REPOS/$project"
    local marker="$REPOS/.${project}-setup-done"
    local cleaned=0

    if [[ -d "$dir" ]]; then
      info "$project: removing $dir"
      rm -rf "$dir"
      cleaned=1
    fi
    if [[ -f "$marker" ]]; then
      rm -f "$marker"
      cleaned=1
    fi

    # Clean stale package artifacts from site-packages
    if [[ "$project" == "pytorch" ]]; then
      rm -rf "$VENV"/lib/python*/site-packages/torch/{_inductor,csrc,share}
      # Remove editable install registration
      rm -f "$VENV"/lib/python*/site-packages/__editable__*torch*
      rm -rf "$VENV"/lib/python*/site-packages/torch-*.dist-info
    fi

    if [[ $cleaned -eq 0 ]]; then
      info "$project: nothing to clean"
    fi
  done

  # Clean venv only if no specific projects given (full clean)
  if [[ ${#args[@]} -eq 0 && -d "$VENV" ]]; then
    info "removing shared venv at $VENV"
    rm -rf "$VENV"
  fi
}

usage() {
  cat <<EOF
Usage: nixtorch <command> [options] [projects...]

Commands:
  build [--force] [--update]   Build/install projects (idempotent)
  status                       Show environment info and project state
  clean [projects...]          Remove repos, markers (and venv if no project specified)

Flags:
  --force, -f      Full rebuild (clear build marker, re-evaluate dependencies)
  --update, -u     Pull latest code before building

When a project is already built, 'build' re-registers the editable install
without recompiling. Use --force for a full C++ rebuild.

Running 'nixtorch' with no arguments opens an interactive menu.
Enabled projects: ${NIXTORCH_ENABLED_PROJECTS:-none}

Examples:
  nixtorch build pytorch             # build pytorch from source
  nixtorch build                     # interactive project selector
  nixtorch build --force pytorch     # force full C++ rebuild
  nixtorch build --update helion     # pull latest + build/install
  nixtorch status                    # show environment + project state
  nixtorch clean                     # remove everything
  nixtorch clean pytorch             # remove only pytorch repo + marker
EOF
}

# ── Main ──
case "${1:-}" in
  build)  shift; cmd_build "$@" ;;
  status) cmd_status ;;
  clean)  shift; cmd_clean "$@" ;;
  help|--help|-h) usage ;;
  "")
    if has_gum && [[ -t 0 ]]; then
      action=$(gum choose --header "nixtorch" build status clean) || exit 0
      case "$action" in
        build)  cmd_build ;;
        status) cmd_status ;;
        clean)  cmd_clean ;;
      esac
    else
      usage
    fi
    ;;
  *) error "unknown command: $1 (try 'nixtorch help')" ;;
esac
