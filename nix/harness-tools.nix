# The programs the AIProver harness and its setup call, as one profile. The setup links it at
# .aiprover/nix/tools; the harness configuration names its bin/ as rg_dir. Lean is not here:
# elan installs the toolchain into ~/.elan, where the harness expects it.
{ pkgs }:
pkgs.buildEnv {
  name = "aiprover-harness-tools";
  paths = with pkgs; [
    python312
    ripgrep
    jq
    git
    curl
    bash
    coreutils
    findutils
    gnused
    gnutar
    gzip
  ];
}
