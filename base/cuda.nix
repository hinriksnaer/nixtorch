# CUDA-specific packages and environment variables.
# Provides the GPU toolchain base for all CUDA project modules.
# Optionally accepts a cudaVersion (e.g. "12.6", "13") to pin a specific
# CUDA toolkit. Defaults to nixpkgs' current default when null.
{
  pkgs,
  cudaVersion ? null,
}: let
  cudaPackages =
    if cudaVersion != null
    then pkgs."cudaPackages_${builtins.replaceStrings ["."] ["_"] cudaVersion}"
    else pkgs.cudaPackages;
  cudaToolkit = cudaPackages.cudatoolkit;
  cudnn = cudaPackages.cudnn;
  cudaGcc = cudaPackages.backendStdenv.cc;
in {
  packages = [
    cudaToolkit
    cudnn
    cudnn.include
    cudnn.lib
    cudaGcc # CUDA backend GCC (version matched to CUDA toolkit)
  ];

  env = {
    CUDA_HOME = "${cudaToolkit}";
    CUDA_PATH = "${cudaToolkit}";
    CUDAHOSTCXX = "${cudaGcc}/bin/g++";
    CMAKE_CUDA_HOST_COMPILER = "${cudaGcc}/bin/g++";
    # Pin compilers to CUDA backend GCC for both CMake and Make.
    # Prevents clang (from Helion) from being used as host compiler.
    CMAKE_C_COMPILER = "${cudaGcc}/bin/gcc";
    CMAKE_CXX_COMPILER = "${cudaGcc}/bin/g++";
    CC = "${cudaGcc}/bin/gcc";
    CXX = "${cudaGcc}/bin/g++";
    CMAKE_PREFIX_PATH = "${cudaToolkit}:${pkgs.python3}";
    CUDNN_INCLUDE_DIR = "${cudnn.include}/include";
    CUDNN_LIB_DIR = "${cudnn.lib}/lib";
    CUDNN_INCLUDE_PATH = "${cudnn.include}/include";
    CUDNN_LIBRARY_PATH = "${cudnn.lib}/lib";
    CPATH = "${cudaToolkit}/include:${cudnn.include}/include";
    LIBRARY_PATH = "${cudaToolkit}/lib";
    # Disable _FORTIFY_SOURCE for nvcc -- glibc's fortified headers use
    # GCC builtins (__builtin___vfprintf_chk) that nvcc doesn't support.
    NVCC_PREPEND_FLAGS = "-U_FORTIFY_SOURCE";
    # NVCUFLAGS is used by NCCL's Makefile for nvcc flags.
    NVCUFLAGS = "-U_FORTIFY_SOURCE";
  };

  # Exposed for LD_LIBRARY_PATH construction in devshell.nix
  libPath = pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    cudaToolkit
    cudnn.lib
  ];
}
