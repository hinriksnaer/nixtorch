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
  packages = with pkgs;
    [
      clang_20
    ]
    ++ pkgs.lib.optional hasCute pkgs.cudaPackages.cutlass;

  env = {
    HELION_REPO = config.repo or "https://github.com/pytorch/helion.git";
    HELION_BRANCH = config.branch or "main";
    HELION_TORCH_INDEX = config.torchIndex or "nightly/cu130";
    HELION_BACKENDS = builtins.concatStringsSep "," backends;
    HELION_PIP_EXTRAS = pipExtras;
  };
}
