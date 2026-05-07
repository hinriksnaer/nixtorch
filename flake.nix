{
  description = "nixtorch - CUDA development shell for PyTorch, Helion, and vLLM";

  # ── Binary cache for pre-built CUDA packages ──
  # Nix will prompt to trust this substituter on first use.
  # The official Hydra (cache.nixos.org) does not build unfree CUDA packages.
  nixConfig = {
    extra-substituters = ["https://cache.nixos-cuda.org"];
    extra-trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        # Only allow CUDA-related unfree packages (cudatoolkit, cudnn, cutlass, etc.)
        # rather than blanket allowUnfree = true.
        allowUnfreePredicate =
          nixpkgs.legacyPackages.${system}._cuda.lib.allowUnfreeCudaPredicate;
      };
    };
  in {
    # ── Formatter (nix fmt) ──
    formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;

    # ── Checks (nix flake check) ──
    checks.${system} = {
      devShell = self.devShells.${system}.default;
    };

    # ── Configurable dev shell constructor ──
    # Usage from another flake:
    #   nixtorch.lib.mkDevShell {
    #     cudaVisibleDevices = "0,1";
    #     projects.pytorch = { cudaArch = "8.0"; };
    #   };
    # Projects are enabled by presence in the attrset.
    # Omit a project to disable it.
    lib.mkDevShell = {
      projects ? {},
      cudaVisibleDevices ? "",
    }: let
      cli = import ./cli {inherit pkgs;};
    in
      import ./shell.nix {
        inherit pkgs projects cudaVisibleDevices cli;
        root = self;
      };

    # ── Workspace template ──
    # nix flake init -t github:hinriksnaer/nixtorch
    templates.default = {
      path = ./template;
      description = "nixtorch workspace with all defaults";
      welcomeText = ''
        nixtorch workspace created.
        Edit flake.nix to change settings, then run: nix develop
        To build pytorch: nixtorch build pytorch
      '';
    };

    # ── Default dev shell (team defaults) ──
    # nix develop github:hinriksnaer/nixtorch
    devShells.${system}.default = self.lib.mkDevShell {
      projects = {
        pytorch = {
          repo = "https://github.com/pytorch/pytorch.git";
          branch = "viable/strict";
          cudaArch = "9.0";
          buildTests = false;
          maxJobs = 32;
        };
        helion = {
          repo = "https://github.com/pytorch/helion.git";
          branch = "main";
          torchIndex = "nightly/cu130";
          backends = ["cute"];
        };
      };
    };
  };
}
