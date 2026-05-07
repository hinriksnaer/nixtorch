# Common build tooling shared across all project modules.
# Python, build tools, and compilation utilities.
{pkgs}: {
  packages = with pkgs; [
    # Python
    python3
    python3Packages.pip
    python3Packages.virtualenv
    python3Packages.debugpy # DAP adapter for neovim
    uv

    # Build tools
    cmake
    ninja
    gnumake
    pkg-config
    zlib
    glibc.bin
    ccache
  ];
}
