{
  inputs.nixtorch.url = "github:hinriksnaer/nixtorch";
  outputs = {nixtorch, ...}: {
    devShells.x86_64-linux.default = nixtorch.lib.mkDevShell {
      cudaVisibleDevices = ""; # "" = all GPUs, or e.g. "0,1"
      workspace = "$HOME/workspace"; # where projects are cloned and built

      projects.pytorch = {
        repo = "https://github.com/pytorch/pytorch.git";
        branch = "viable/strict";
        cudaArch = "9.0"; # e.g. "8.0", "8.0;9.0"
        maxJobs = 16;
        buildTests = false;
        # env = {}; # override any pytorch build env var
      };

      projects.helion = {
        repo = "https://github.com/pytorch/helion.git";
        branch = "main";
        torchIndex = "nightly/cu130";
        backends = ["cuda"]; # add "cute" for CUTLASS
      };

      # Uncomment to enable vllm:
      # projects.vllm = {
      #   repo = "https://github.com/vllm-project/vllm.git";
      #   branch = "main";
      #   torchIndex = "nightly/cu130";
      # };
    };
  };
}
