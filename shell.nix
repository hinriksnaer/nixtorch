# Shared CUDA development shell.
# Works on any host with Nix + NVIDIA drivers.
#
# Imports base/ for shared tooling and CUDA, then merges per-project
# modules from projects/ based on the projects argument.
#
# Usage: nix develop github:hinriksnaer/nixtorch
#    or: cd into a project dir with .envrc -> direnv auto-enters
{
  pkgs,
  root,
  cli,
  projects ? {},
  cudaVisibleDevices ? "",
  cudaVersion ? null,
  workspace ? "$HOME/workspace",
}: let
  lib = pkgs.lib;

  # ── Base layers ──
  tooling = import ./base/tooling.nix {inherit pkgs;};
  cudaBase = import ./base/cuda.nix {inherit pkgs cudaVersion;};

  # ── Per-project modules (imported only when enabled) ──
  # Build order matters: pytorch first (provides torch), then downstream.
  projectOrder = ["pytorch" "helion" "vllm"];

  projectModules = {
    pytorch = import ./projects/pytorch {
      inherit pkgs;
      config = projects.pytorch or {};
    };
    helion = import ./projects/helion {
      inherit pkgs;
      config = projects.helion or {};
    };
    vllm = import ./projects/vllm {
      inherit pkgs;
      config = projects.vllm or {};
    };
  };

  enabledNames =
    builtins.filter (name: projects ? ${name}) projectOrder;

  enabledModules = map (name: projectModules.${name}) enabledNames;

  # ── Merge packages and env vars from all enabled modules ──
  mergedPackages = lib.concatMap (m: m.packages) enabledModules;
  mergedEnv = lib.foldl' (a: b: a // b) {} (map (m: m.env) enabledModules);
in
  pkgs.mkShell ({
      name = "nixtorch";

      # Disable _FORTIFY_SOURCE -- glibc 2.42's fortified headers use GCC
      # builtins (__builtin___vfprintf_chk) that nvcc doesn't support.
      # This must be at the mkShell level because NCCL's Makefile overwrites
      # NVCUFLAGS and doesn't read env vars for nvcc flags.
      hardeningDisable = ["fortify"];

      packages = [cli] ++ tooling.packages ++ cudaBase.packages ++ mergedPackages;

      NIXTORCH_ENABLED_PROJECTS = builtins.concatStringsSep " " enabledNames;

      # ── Shell hook (runtime-dependent vars only) ──
      # workspace uses $HOME which must be expanded by bash, not Nix.
      shellHook = ''
        export NIXTORCH_ROOT="${root}"
        export NIXTORCH_WORKSPACE="${workspace}"
        export CCACHE_DIR="$HOME/.cache/ccache"
        ${lib.optionalString (cudaVisibleDevices != "") ''export CUDA_VISIBLE_DEVICES="${cudaVisibleDevices}"''}

        # Symlink host NVIDIA driver libs into a clean directory so we can add
        # them to LD_LIBRARY_PATH without exposing the host glibc.
        _nv="$HOME/.cache/nixtorch/nvidia-driver-libs"
        mkdir -p "$_nv"
        for _f in /usr/lib64/libcuda.so* /usr/lib64/libnvidia*.so* /usr/lib64/libnvcuvid*.so*; do
          [ -e "$_f" ] && ln -sf "$_f" "$_nv/" 2>/dev/null
        done
        export LD_LIBRARY_PATH="${cudaBase.libPath}:$_nv''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

        # Activate shared venv if it exists
        if [ -f "$NIXTORCH_WORKSPACE/.venv/bin/activate" ]; then
          source "$NIXTORCH_WORKSPACE/.venv/bin/activate"
        fi
      '';
    }
    // cudaBase.env // mergedEnv)
