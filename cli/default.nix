# CLI packaging. Uses writeShellApplication for shellcheck
# validation, set -euo pipefail, and runtimeInputs.
{pkgs}:
pkgs.writeShellApplication {
  name = "nixtorch";
  runtimeInputs = with pkgs; [git gum];
  text = builtins.readFile ./nixtorch.sh;
  excludeShellChecks = ["SC1091" "SC2016" "SC2046" "SC2086" "SC2155" "SC2206"];
}
