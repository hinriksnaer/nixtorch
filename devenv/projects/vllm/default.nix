# vLLM project module.
# Returns packages and env vars for building vLLM.
{
  pkgs,
  config,
}: {
  packages = [];

  env = {
    VLLM_REPO = config.repo or "https://github.com/vllm-project/vllm.git";
    VLLM_BRANCH = config.branch or "main";
    VLLM_TARGET_DEVICE = "cuda";
    VLLM_TORCH_INDEX = config.torchIndex or "nightly/cu130";
  };
}
