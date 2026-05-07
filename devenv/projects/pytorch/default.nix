# PyTorch project module.
# Returns packages and env vars needed to build PyTorch from source.
{
  pkgs,
  config,
}: let
  cudaArch = config.cudaArch or "9.0";
  maxJobs = toString (config.maxJobs or 32);
  buildTests =
    if (config.buildTests or false)
    then "1"
    else "0";
in {
  packages = with pkgs; [
    gfortran
    openblas
    libuv
    libpng
    libjpeg
    python3Packages.pyyaml
    python3Packages.typing-extensions
    python3Packages.setuptools
  ];

  env = {
    PYTORCH_REPO = config.repo or "https://github.com/pytorch/pytorch.git";
    PYTORCH_BRANCH = config.branch or "viable/strict";

    # Build flags
    USE_CUDA = "1";
    USE_CUDNN = "1";
    USE_NCCL = "1";
    USE_SYSTEM_NCCL = "0";
    USE_CUFILE = "OFF";
    USE_NVSHMEM = "OFF";
    USE_KINETO = "1";
    USE_FBGEMM = "0";
    USE_NNPACK = "0";
    USE_QNNPACK = "0";
    USE_XNNPACK = "0";
    USE_PRECOMPILED_HEADERS = "1";
    TORCH_CUDA_ARCH_LIST = cudaArch;
    BUILD_TEST = buildTests;
    MAX_JOBS = maxJobs;

    # ccache
    CMAKE_C_COMPILER_LAUNCHER = "ccache";
    CMAKE_CXX_COMPILER_LAUNCHER = "ccache";
    CMAKE_CUDA_COMPILER_LAUNCHER = "ccache";
    CCACHE_MAXSIZE = "25G";
    CCACHE_NOHASHDIR = "true";
  };
}
