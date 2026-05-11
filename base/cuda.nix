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
    # Pin compilers to the CUDA backend GCC for ABI compatibility.
    # cudaGcc's cc-wrapper setup hook also sets CC/CXX, but these
    # explicit vars serve as documentation and fallback.
    CC = "${cudaGcc}/bin/gcc";
    CXX = "${cudaGcc}/bin/g++";
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
