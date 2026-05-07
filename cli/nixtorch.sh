# nixtorch -- CLI for managing the nixtorch development environment.
# Must be run inside the nix develop shell.
#
# Build logic lives in devenv/projects/<name>/setup.sh -- this CLI
# just orchestrates them in the correct order.

REPOS="$HOME/workspace"
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

# ── Commands ──

cmd_build() {
  local force=0
  local args=()

  # Parse --force flag
  for arg in "$@"; do
    case "$arg" in
      --force|-f) force=1 ;;
      *) args+=("$arg") ;;
    esac
  done

  # No projects specified -- prompt with gum or build all enabled
  if [[ ${#args[@]} -eq 0 ]]; then
    if has_gum && [[ -t 0 ]]; then
      local selected
      selected=$(gum choose --no-limit --header "Select projects to build:" $(enabled_projects) </dev/tty) || exit 0
      if [[ -z "$selected" ]]; then
        info "no projects selected"
        exit 0
      fi
      args=($selected)
    fi
  fi

  local projects
  projects=$(resolve_projects "${args[@]+"${args[@]}"}")

  for project in $projects; do
    local setup="$NIXTORCH_ROOT/devenv/projects/${project}/setup.sh"
    local marker="$REPOS/.${project}-setup-done"

    if [[ ! -f "$setup" ]]; then
      error "$project: no setup script found at $setup"
    fi

    # --force: confirm then remove marker so setup.sh re-runs
    if [[ $force -eq 1 && -f "$marker" ]]; then
      if has_gum; then
        gum confirm "Force rebuild $project? This clears the build marker." || continue
      fi
      info "$project: clearing build marker"
      rm -f "$marker"
    fi

    info "$project: running setup"
    local start=$SECONDS
    bash "$setup"
    local elapsed=$(( SECONDS - start ))
    info "$project: done ($(fmt_duration $elapsed))"
  done
}

cmd_update() {
  # No args: update nixtorch itself and re-enter the shell
  if [[ $# -eq 0 ]]; then
    if [[ "$NIXTORCH_ROOT" == /nix/store/* ]]; then
      info "updating nixtorch from github..."
      exec nix develop github:hinriksnaer/nixtorch --refresh
    else
      info "updating local flake at $NIXTORCH_ROOT..."
      nix flake update --flake "$NIXTORCH_ROOT"
      exec nix develop "$NIXTORCH_ROOT" --refresh
    fi
  fi

  # Args given: pull latest for specified projects and rebuild if already built
  local projects
  projects=$(resolve_projects "$@")

  for project in $projects; do
    local dir="$REPOS/$project"
    local branch
    branch=$(get_branch "$project")
    local marker="$REPOS/.${project}-setup-done"

    if [[ ! -d "$dir" ]]; then
      warn "$project: not cloned, skipping (run 'nixtorch build $project' first)"
      continue
    fi

    info "$project: pulling latest ($branch)"
    git -C "$dir" fetch origin
    git -C "$dir" checkout "$branch"
    git -C "$dir" pull --ff-only
    git -C "$dir" submodule update --init --recursive

    # Rebuild if previously built
    if [[ -f "$marker" ]]; then
      local setup="$NIXTORCH_ROOT/devenv/projects/${project}/setup.sh"
      if [[ -f "$setup" ]]; then
        info "$project: rebuilding..."
        rm -f "$marker"
        local start=$SECONDS
        bash "$setup"
        local elapsed=$(( SECONDS - start ))
        info "$project: done ($(fmt_duration $elapsed))"
      fi
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
  # Full clean (no specific projects) -- confirm first
  if [[ $# -eq 0 ]]; then
    if has_gum; then
      gum confirm "Remove all project repos, build markers, and shared venv?" || exit 0
    fi
  fi

  local projects
  projects=$(resolve_projects "$@")

  for project in $projects; do
    local dir="$REPOS/$project"
    local marker="$REPOS/.${project}-setup-done"

    if [[ -d "$dir" ]]; then
      info "$project: removing $dir"
      rm -rf "$dir"
    fi
    if [[ -f "$marker" ]]; then
      rm -f "$marker"
    fi

    if [[ ! -d "$dir" && ! -f "$marker" ]]; then
      info "$project: nothing to clean"
    fi
  done

  # Clean venv only if no specific projects given (full clean)
  if [[ $# -eq 0 && -d "$VENV" ]]; then
    info "removing shared venv at $VENV"
    rm -rf "$VENV"
  fi
}

usage() {
  cat <<EOF
Usage: nixtorch <command> [options] [projects...]

Commands:
  build [--force]        Clone, build, and install projects from source (idempotent)
  status                 Show environment info and state of all projects
  update                 Update nixtorch itself and re-enter the shell
  update <projects...>   Pull latest code for projects and rebuild
  clean                  Remove project repos and build markers (and venv if no projects specified)

Options:
  --force, -f      Force rebuild (clear build marker before running setup)

Projects are built in dependency order (pytorch first, then downstream).
If no projects are specified, an interactive selector is shown.
Enabled projects: ${NIXTORCH_ENABLED_PROJECTS:-none}

Examples:
  nixtorch build pytorch             # build pytorch from source
  nixtorch build                     # interactive project selector
  nixtorch build --force pytorch     # force rebuild pytorch from scratch
  nixtorch status                    # show environment + project state
  nixtorch update                    # update nixtorch and re-enter shell
  nixtorch update helion             # pull latest helion code and rebuild
  nixtorch clean                     # remove everything (repos + markers + venv)
  nixtorch clean pytorch             # remove only pytorch repo + marker
EOF
}

# ── Main ──
case "${1:-}" in
  build)  shift; cmd_build "$@" ;;
  status) cmd_status ;;
  update) shift; cmd_update "$@" ;;
  clean)  shift; cmd_clean "$@" ;;
  help|--help|-h) usage ;;
  "") usage ;;
  *) error "unknown command: $1 (try 'nixtorch help')" ;;
esac
