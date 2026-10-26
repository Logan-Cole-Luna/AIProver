{
  description = "AIProver: the harness and the orchestration, pinned as submodules, and their setup";

  # The harness virtualenvs and the orchestration tools are packages of orchestration/flake.nix,
  # built from the checkout by scripts/setup.sh; this flake holds the setup commands, the
  # harness tools, and the shell. nixpkgs is locked at the revision of orchestration/flake.lock.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

  outputs =
    { self, nixpkgs }:
    let
      # Windows is WSL2 running the x86_64-linux packages.
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # One app per setup command; each runs scripts/setup.sh of the checkout it is started in,
      # since the setup writes its configuration and environment links into that checkout.
      setupApp =
        pkgs: component:
        let
          program = pkgs.writeShellApplication {
            name = "aiprover-setup-${component}";
            runtimeInputs = [ pkgs.git ];
            text = ''
              root=$(git rev-parse --show-toplevel 2>/dev/null || true)
              if ! grep -qs 'path = orchestration' "$root/.gitmodules"; then
                echo "run inside a checkout of the AIProver repository" >&2
                exit 1
              fi
              exec sh "$root/scripts/setup.sh" ${component} "$@"
            '';
          };
        in
        {
          type = "app";
          program = "${program}/bin/aiprover-setup-${component}";
        };
    in
    {
      packages = forAllSystems (system: rec {
        harness-tools = import ./nix/harness-tools.nix { pkgs = nixpkgs.legacyPackages.${system}; };
        default = harness-tools;
      });

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          setup-harness = setupApp pkgs "harness";
          setup-orchestration = setupApp pkgs "orchestration";
          setup = setupApp pkgs "all";
          default = self.apps.${system}.setup;
        }
      );

      # `nix develop`, or `direnv allow` once: the harness tools, the orchestration tools that the
      # setup linked, and the harness configuration of the setup.
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = [ self.packages.${system}.harness-tools ];
          shellHook = ''
            export AIPROVER_CONFIG="$PWD/.aiprover/aiprover.toml"
            export PATH="$PWD/harness/AIProver_plugin/bin:$PWD/orchestration/aiprover/nix/tools/bin:$PATH"
          '';
        };
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
