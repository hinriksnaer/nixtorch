# Common build tooling shared across all project modules.
# Python, build tools, and compilation utilities.
{pkgs}: {
  packages = with pkgs; [
    # Python: single wrapped interpreter. Using python3Packages.* directly
    # exports their site-packages via PYTHONPATH, which leaks python3.14
    # packages into project virtualenvs and shadows their own packages
    # (e.g. platformdirs' pytest plugin).
    (python3.withPackages (ps: [
      ps.pip
      ps.virtualenv
      ps.debugpy # DAP adapter for neovim
    ]))
    uv

    # Build tools
    cmake
    ninja
    gnumake
    pkg-config
    zlib
    glibc.bin
    ccache
    which # required by NCCL's Makefile
    llvmPackages.openmp # omp.h / libomp for OpenMP support
  ];
}
