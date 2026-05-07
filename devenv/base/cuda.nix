# CUDA-specific packages and environment variables.
# Provides the GPU toolchain base for all CUDA project modules.
{pkgs}: let
  inherit (pkgs) cudaPackages;
  cudaToolkit = cudaPackages.cudatoolkit;
  cudnn = cudaPackages.cudnn;
  cudaGcc = cudaPackages.backendStdenv.cc;
in {
  packages = [
    cudaToolkit
    cudnn
    cudnn.include
    cudnn.lib
    cudaGcc # GCC 14 (CUDA 12.9 requires <=14)
  ];

  env = {
    CUDA_HOME = "${cudaToolkit}";
    CUDA_PATH = "${cudaToolkit}";
    CMAKE_PREFIX_PATH = "${cudaToolkit}:${pkgs.python3}";
    CUDNN_INCLUDE_DIR = "${cudnn.include}/include";
    CUDNN_LIB_DIR = "${cudnn.lib}/lib";
    CUDNN_INCLUDE_PATH = "${cudnn.include}/include";
    CUDNN_LIBRARY_PATH = "${cudnn.lib}/lib";
    CPATH = "${cudaToolkit}/include:${cudnn.include}/include";
    LIBRARY_PATH = "${cudaToolkit}/lib";
  };

  # Exposed for LD_LIBRARY_PATH construction in devshell.nix
  libPath = pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    cudaToolkit
    cudnn.lib
  ];
}
