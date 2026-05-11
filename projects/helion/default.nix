# Helion project module.
# Returns packages and env vars for the Helion compiler.
{
  pkgs,
  config,
}: let
  backends = config.backends or ["cuda"];
  hasCute = builtins.elem "cute" backends;
  pipExtras = let
    extras = pkgs.lib.optional hasCute "cute-cu12";
    joined = builtins.concatStringsSep "," extras;
  in
    if joined != ""
    then "[${joined}]"
    else "";
in {
  # NOTE: Do NOT add clang here. Helion is pure Python (hatchling build)
  # and does not need a system clang. Adding a cc-wrapper package like
  # clang_20 triggers Nix's setup hook which unconditionally exports
  # CC/CXX, overriding the CUDA backend GCC and breaking PyTorch's build
  # (tensorpipe template errors, -fclang-abi-compat=17 forwarded to GCC).
  packages = pkgs.lib.optional hasCute pkgs.cudaPackages.cutlass;

  env = {
    HELION_REPO = config.repo or "https://github.com/pytorch/helion.git";
    HELION_BRANCH = config.branch or "main";
    HELION_TORCH_INDEX = config.torchIndex or "nightly/cu130";
    HELION_BACKENDS = builtins.concatStringsSep "," backends;
    HELION_PIP_EXTRAS = pipExtras;
  };
}
