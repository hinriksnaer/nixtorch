# nixtorch

Nix flake that gives you a CUDA development shell for building PyTorch, Helion, and vLLM from source.

Handles CUDA 12.9, cuDNN 9.13, GCC 14, Python, cmake, ninja, ccache, and all the Nix-specific
patches needed to make GPU builds work (FindCUDAToolkit, driver lib symlinks, etc.).

## Quick start

```sh
sudo dnf install nix
nix develop github:hinriksnaer/nixtorch
nixtorch build pytorch
```

This enters the dev shell and builds PyTorch from source into `~/workspace/`.
First run takes a while (compiles from source). Subsequent runs are idempotent.

## Entering the shell

Default:

```sh
nix develop github:hinriksnaer/nixtorch
```

With a custom config (see [Configuration](#configuration)):

```sh
nix develop ~/nixtorch-config
```

## CLI

```
nixtorch build [--force] [projects...]   # clone + build from source
nixtorch status                          # show environment and project state
nixtorch update                          # update nixtorch and re-enter shell
nixtorch update <projects...>            # pull latest code and rebuild
nixtorch customize                       # generate local config with all defaults
nixtorch apply                           # re-enter shell with local config changes
nixtorch clean [projects...]             # remove repos, markers, venv
```

`--force` clears the build marker so setup runs again from scratch.
Projects build in dependency order: pytorch first, then helion/vllm.

Running `nixtorch build` with no arguments opens an interactive project selector.

## Updating

Update nixtorch itself (fetches latest from GitHub, re-enters the shell):

```sh
nixtorch update
```

Update a project (pulls latest code, rebuilds if previously built):

```sh
nixtorch update pytorch
```

If you're on an older version without the `update` command:

```sh
nix develop github:hinriksnaer/nixtorch --refresh
```

## Configuration

The default shell enables pytorch and helion. To customize, run:

```sh
nixtorch customize
```

This generates a local config directory with a `flake.nix` containing all defaults.
Edit the file to change settings, then run `nixtorch apply` to apply your changes.

Here are all available options with their defaults:

```nix
{
  inputs.nixtorch.url = "github:hinriksnaer/nixtorch";
  outputs = {nixtorch, ...}: {
    devShells.x86_64-linux.default = nixtorch.lib.mkDevShell {
      cudaVisibleDevices = "";  # "" = all GPUs, or e.g. "0,1"

      projects.pytorch = {
        repo = "https://github.com/pytorch/pytorch.git";
        branch = "viable/strict";
        cudaArch = "9.0";       # e.g. "8.0", "8.0;9.0"
        maxJobs = 32;
        buildTests = false;

        # Override or add any PyTorch build environment variable.
        # These merge on top of the defaults below.
        env = {
          # USE_FBGEMM = "1";
          # USE_NNPACK = "1";
          # CCACHE_MAXSIZE = "50G";
        };
      };

      projects.helion = {
        repo = "https://github.com/pytorch/helion.git";
        branch = "main";
        torchIndex = "nightly/cu130";
        backends = ["cuda"];    # add "cute" for CUTLASS support
      };

      projects.vllm = {
        repo = "https://github.com/vllm-project/vllm.git";
        branch = "main";
        torchIndex = "nightly/cu130";
      };
    };
  };
}
```

### PyTorch env defaults

These are the build flags set by default. Any of them can be overridden via `projects.pytorch.env`:

```
USE_CUDA=1  USE_CUDNN=1  USE_NCCL=1  USE_KINETO=1  USE_PRECOMPILED_HEADERS=1
USE_SYSTEM_NCCL=0  USE_CUFILE=OFF  USE_NVSHMEM=OFF
USE_FBGEMM=0  USE_NNPACK=0  USE_QNNPACK=0  USE_XNNPACK=0
CMAKE_C_COMPILER_LAUNCHER=ccache
CMAKE_CXX_COMPILER_LAUNCHER=ccache
CMAKE_CUDA_COMPILER_LAUNCHER=ccache
CCACHE_MAXSIZE=25G  CCACHE_NOHASHDIR=true
```

### Torch dependency

Helion and vLLM depend on PyTorch. If you build pytorch first, they'll use the
locally compiled version from the shared venv. If pytorch isn't built, they'll
install a nightly wheel automatically.

## What's in the shell

- CUDA 12.9 toolkit + cuDNN 9.13
- GCC 14 (CUDA 12.9 backend compiler)
- Python 3, pip, virtualenv, uv
- cmake, ninja, ccache, pkg-config
- Per-project build flags and env vars
- Host NVIDIA driver libs symlinked for LD_LIBRARY_PATH

## Project layout

```
devenv/
  shell.nix              # dev shell entry point
  base/cuda.nix          # CUDA toolkit + cuDNN
  base/tooling.nix       # Python, cmake, ninja, etc.
  projects/pytorch/      # PyTorch build config + setup script
  projects/helion/       # Helion build config + setup script
  projects/vllm/         # vLLM build config + setup script
cli/nixtorch.sh          # CLI source (packaged via writeShellApplication)
```

## Requirements

- x86_64 Linux with NVIDIA GPU
- Nix with flakes enabled
- NVIDIA drivers installed on the host
