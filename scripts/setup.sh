#!/bin/sh
# scripts/setup.sh harness|orchestration|all [OPTIONS]: the AIProver harness, the orchestration,
# or both, from a checkout of this repository, on Linux, WSL2 or macOS. The flake apps run it:
#
#   nix run .#setup-harness       -- [OPTIONS]      scripts/setup.sh harness
#   nix run .#setup-orchestration -- [OPTIONS]      scripts/setup.sh orchestration
#   nix run .#setup               -- [OPTIONS]      scripts/setup.sh all
#
# Without Nix, run scripts/setup.sh directly: it offers to install Nix first.
#
#   --endpoint URL|none  the model server; none: no server (Claude subagents prove the lemmas)
#   --via HOST           an SSH host that reaches the server (the connection is an SSH tunnel)
#   --handoff FILE       a file on HOST in which a server job writes `node=<n> port=<p>`
#   --user USER          SSH user, when ~/.ssh/config does not set one for HOST
#   --api-key KEY        bearer token of the model server
#   --timeout SEC        wall clock of one AIProver session (default 5400)
#   --max-turns N        turn budget of one AIProver session (default 200)
#   --no-lean            skip the Lean build and the plugin installation
#   --yes                accept every default
#   --dry-run            print what would happen; change nothing
#   --installer official|determinate    the Nix installer, when Nix is missing
# The orchestration accepts further options (orchestration/setup --help); every option is passed
# to it unchanged.
#
# harness:        builds the harness environment into .aiprover/nix/, writes the harness
#                 configuration .aiprover/aiprover.toml (linked from ~/.config/aiprover/), runs
#                 harness/AIProver_plugin/setup.sh lean and aiprover doctor.
# orchestration:  runs orchestration/setup with this repository's harness/ (and the harness's
#                 Lean project, when the harness is set up).
# all:            the harness, then the orchestration on the same Lean project.
# Each installs its Claude Code plugins from the marketplace skill/.
#
# POSIX sh on purpose: it runs before anything else is installed.
set -eu

NIX_FEATURES="nix-command flakes"
# Local end of the harness's SSH tunnel; the orchestration's tunnel uses 18555.
TUNNEL_PORT=18565
# The orchestration's reasoning proxy, the harness's server when no endpoint is given.
PROXY_PORT=18575
LEGACY_PLUGINS="aiprover@aiprover-local aiprover-orchestration@aiprover-orchestration-local"

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'setup: warning: %s\n' "$*" >&2; }
die() {
  printf 'setup: %s\n' "$*" >&2
  exit 1
}
usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

run() {
  if [ "$DRY" = yes ]; then say "would run: $*"; else "$@"; fi
}

nix_cmd() { run nix --extra-experimental-features "$NIX_FEATURES" "$@"; }

# parse_options OPTIONS: the options the harness uses; the others are left to the orchestration.
parse_options() {
  ENDPOINT="" VIA="" SSH_USER="" HANDOFF="" API_KEY=EMPTY TIMEOUT=5400 TURNS=200
  LEAN=yes YES=no DRY=no INSTALLER=official LEAN_PROJECT=""
  while [ $# -gt 0 ]; do
    case "$1" in
    --endpoint) ENDPOINT="${2:?--endpoint needs a value}"; shift ;;
    --endpoint=*) ENDPOINT="${1#*=}" ;;
    --via) VIA="${2:?--via needs a host}"; shift ;;
    --user) SSH_USER="${2:?--user needs a name}"; shift ;;
    --handoff) HANDOFF="${2:?--handoff needs a path}"; shift ;;
    --api-key) API_KEY="${2:?--api-key needs a value}"; shift ;;
    --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift ;;
    --max-turns) TURNS="${2:?--max-turns needs a number}"; shift ;;
    --lean-project) LEAN_PROJECT="${2:?--lean-project needs a path}"; shift ;;
    --installer) INSTALLER="${2:?--installer needs a name}"; shift ;;
    --no-lean) LEAN=no ;;
    --yes | -y) YES=yes ;;
    --dry-run) DRY=yes ;;
    -h | --help) usage; exit 0 ;;
    --*) ;;
    esac
    shift
  done
}

# Submodules and Nix ------------------------------------------------------------------------------

# fetch_submodule PATH: initialized at its pinned commit, unless already checked out (development
# happens inside the submodules). Not recursive: the orchestration uses harness/, not its own
# AIProver/ submodule.
fetch_submodule() {
  [ -e "$1/.git" ] && return
  step "Submodule: $1/"
  run git submodule update --init "$1"
}

load_nix() {
  for profile in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
    # shellcheck disable=SC1090  # the installer's own profile script
    [ -f "$profile" ] && . "$profile"
  done
  command -v nix >/dev/null 2>&1
}

check_nix() {
  if load_nix; then
    step "Nix: $(nix --version)"
    return
  fi
  case "$INSTALLER" in
  official) command="curl -L https://nixos.org/nix/install | sh -s -- --daemon" ;;
  determinate) command="curl -fsSL https://install.determinate.systems/nix | sh -s -- install --prefer-upstream-nix" ;;
  *) die "unknown installer $INSTALLER (official|determinate)" ;;
  esac
  step "Nix: not found"
  say "The $INSTALLER installer would run (it needs sudo once, to create /nix):"
  say "  $command"
  if [ "$DRY" = yes ]; then return; fi
  printf 'Install Nix now? [y/N] '
  read -r answer || answer=""
  case "$answer" in [Yy]*) ;; *) die "install Nix, then run the setup again" ;; esac
  sh -c "$command"
  load_nix || die "Nix installed but not found: open a new terminal and run the setup again"
}

# Harness -----------------------------------------------------------------------------------------

# write_harness_config: .aiprover/aiprover.toml, in the format of
# harness/AIProver_plugin/aiprover.toml, for the endpoint of the options.
write_harness_config() {
  config=.aiprover/aiprover.toml
  if [ -z "$ENDPOINT$HANDOFF" ] && [ -f "$config" ]; then
    step "Harness configuration: keeping $config (pass --endpoint to replace it)"
    return
  fi
  if [ -z "$ENDPOINT$HANDOFF" ]; then
    [ "$YES" = yes ] && die "no endpoint configured: pass --endpoint URL or none (see --help)"
    printf 'Model server URL (http://host:port; empty for none): '
    read -r ENDPOINT || ENDPOINT=""
    ENDPOINT=${ENDPOINT:-none}
  fi
  mode=direct api_base="" remote_host="" remote_port=80 socket=""
  case "$ENDPOINT" in
  none) api_base="http://127.0.0.1:$PROXY_PORT/v1" ;;
  http://* | https://*) api_base="${ENDPOINT%/}" ;;
  "") ;;
  *) die "unknown endpoint $ENDPOINT: give the model server's URL (http://host:port) or none" ;;
  esac
  if [ -n "$VIA" ]; then
    mode=ssh
    # shellcheck disable=SC2088  # a literal ~, expanded by the AIProver CLI
    socket="~/.ssh/aiprover-$(printf '%s' "$VIA" | tr -c 'A-Za-z0-9.-' '_').sock"
    address=${ENDPOINT#*://}
    address=${address%%/*}
    remote_host=${address%:*}
    case "$address" in
    *:*) remote_port=${address##*:} ;;
    *) case "$ENDPOINT" in https://*) remote_port=443 ;; esac ;;
    esac
    api_base=""
  fi
  [ "$mode" = ssh ] || [ -n "$api_base" ] || die "--handoff needs --via HOST"
  case "$api_base" in "" | */v1) ;; *) api_base="$api_base/v1" ;; esac
  root=$(pwd)
  step "Harness configuration: $config ($mode${api_base:+, $api_base}${VIA:+, via $VIA})"
  content=$(
    cat <<EOF
# AIProver harness configuration, written by scripts/setup.sh for this device. Same format as
# harness/AIProver_plugin/aiprover.toml. Edit it freely; the setup keeps it unless --endpoint
# is given. After an edit: harness/AIProver_plugin/bin/aiprover doctor

[endpoint]
mode = "$mode"
# ssh mode: the host you SSH into, and the model's address as seen from it. With server_handoff
# set, the node and port are read from that file on ssh_host (a server job writes it).
ssh_host = "$VIA"
ssh_user = "$SSH_USER"
ssh_port = 22
remote_host = "$remote_host"
remote_port = $remote_port
server_handoff = "$HANDOFF"
control_socket = "$socket"
ssh_options = []
local_port = $TUNNEL_PORT
# direct mode: the server itself.
api_base = "$api_base"
api_key = "$API_KEY"
# Served model id; empty = the first id /v1/models reports.
model = ""

[runtime]
work_root = "$root/.aiprover/work"
timeout_sec = $TIMEOUT
max_turns = $TURNS

[paths]
lean_project = "${LEAN_PROJECT:-$root/.aiprover/lean_project}"
elan_home = "~/.elan"
vibe_venv = "$root/.aiprover/nix/venv_vibe"
mcp_venv = "$root/.aiprover/nix/venv_mcp"
rg_dir = "$root/.aiprover/nix/tools/bin"
EOF
  )
  if [ "$DRY" = yes ]; then
    printf '%s\n' "$content"
  else
    printf '%s\n' "$content" > "$config"
  fi
}

setup_harness() {
  fetch_submodule harness
  fetch_submodule orchestration
  # The virtualenvs are packages of orchestration/flake.nix, the same derivations its own setup
  # builds.
  step "Environment: harness tools and virtualenvs (the first build downloads a few GB)"
  run mkdir -p .aiprover/nix
  nix_cmd build .#harness-tools --out-link .aiprover/nix/tools
  nix_cmd build ./orchestration#venv-vibe --out-link .aiprover/nix/venv_vibe
  nix_cmd build ./orchestration#venv-mcp --out-link .aiprover/nix/venv_mcp
  write_harness_config
  AIPROVER_CONFIG="$(pwd)/.aiprover/aiprover.toml"
  PATH="$(pwd)/.aiprover/nix/tools/bin:$PATH"
  export AIPROVER_CONFIG PATH
  # An installed plugin runs from a cached copy and finds its configuration here.
  run mkdir -p "$HOME/.config/aiprover"
  run ln -sfn "$AIPROVER_CONFIG" "$HOME/.config/aiprover/aiprover.toml"
  if [ "$LEAN" = yes ]; then
    step "Lean (the first setup downloads Mathlib's cache, ~5 GB)"
    run bash harness/AIProver_plugin/setup.sh lean
  fi
  step "Doctor"
  run harness/AIProver_plugin/bin/aiprover doctor \
    || warn "some rows failed; without a model server, the model rows are expected to fail"
}

# Orchestration -----------------------------------------------------------------------------------

setup_orchestration() {
  fetch_submodule harness
  fetch_submodule orchestration
  shared=""
  if [ -z "$LEAN_PROJECT" ] && [ -d .aiprover/lean_project ]; then
    shared="--lean-project $(pwd)/.aiprover/lean_project"
  fi
  step "Orchestration: orchestration/setup --harness $(pwd)/harness --no-plugin $shared $*"
  # shellcheck disable=SC2086  # $shared is empty or one option with its value
  (cd orchestration && sh ./setup --harness ../harness --no-plugin $shared "$@")
}

# Plugins -----------------------------------------------------------------------------------------

# install_plugins NAME...: from the marketplace skill/, replacing installs of the former
# per-repository marketplaces.
install_plugins() {
  [ "$LEAN" = yes ] || return 0
  step "Claude Code plugins: $* (marketplace skill/)"
  if ! command -v claude >/dev/null 2>&1; then
    say "The claude CLI is not on PATH; install from the Claude Code app instead:"
    say "  /plugin marketplace add $(pwd)/skill"
    for name in "$@"; do say "  /plugin install $name@aiprover"; done
    return 0
  fi
  [ "$DRY" = yes ] && { say "would install: $*"; return 0; }
  for legacy in $LEGACY_PLUGINS; do claude plugin uninstall "$legacy" >/dev/null 2>&1 || true; done
  claude plugin marketplace add "$(pwd)/skill" >/dev/null 2>&1 \
    || claude plugin marketplace update aiprover >/dev/null 2>&1 || true
  for name in "$@"; do
    # Reinstalled: an installed plugin runs from a cached copy refreshed only on installation.
    claude plugin uninstall "$name@aiprover" >/dev/null 2>&1 || true
    claude plugin install "$name@aiprover" --scope user >/dev/null \
      || die "could not install $name@aiprover"
  done
  say "Installed; restart open Claude Code sessions to load them."
}

main() {
  component="${1:-}"
  [ $# -gt 0 ] && shift
  case "$component" in
  harness | orchestration | all) ;;
  -h | --help) usage; exit 0 ;;
  *) usage; exit 2 ;;
  esac
  parse_options "$@"
  cd "$(dirname "$0")/.."
  [ -f flake.nix ] && [ -f .gitmodules ] || die "scripts/setup.sh belongs to the AIProver repository"
  check_nix
  case "$component" in
  harness)
    setup_harness
    install_plugins aiprover
    ;;
  orchestration)
    setup_orchestration "$@"
    install_plugins aiprover-orchestration
    ;;
  all)
    setup_harness
    setup_orchestration "$@"
    install_plugins aiprover aiprover-orchestration
    ;;
  esac
  step "Done: ask Claude Code for the aiprover-autoformalize or aiprover-captain skill; see README.md"
}

main "$@"
