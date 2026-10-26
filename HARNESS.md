# AIProver harness

The harness ([PrithwishJana/AIProver](https://github.com/PrithwishJana/AIProver), submodule
`harness/`) runs the AIProver model as a Lean agent. Each job is a complete agentic session of
up to 200 turns: the model writes Lean, compiles it, searches Mathlib and cslib, reads goals, and
repairs the file. The harness, the Lean toolchain, and the tools run on the user's machine; only
model inference runs on the GPU server.

It serves in three modes, all within `harness/AIProver_plugin/`:

| Mode | Entry point | Judge of the result |
| --- | --- | --- |
| Standalone | `bin/aiprover` (`submit`, `wait`, `result`, `check`, `probe`, `search`) | the user |
| Claude Code | the skill `aiprover-autoformalize` of the plugin `aiprover` | Claude Code |
| Codex | the same skill, installed by `harness/AIProver_plugin/setup.sh codex` | Codex |

The harness's own documentation covers each mode in full:
[README](harness/README.md), [plugin README](harness/AIProver_plugin/README.md), and
[STARTUP](harness/AIProver_plugin/STARTUP.md), which maps every doctor row to its fix.

## Setup

```bash
nix run .#setup-harness -- --endpoint http://<host>:<port>
```

The command takes the following steps:

1. It builds the harness tools (`.#harness-tools`) and the two Python virtualenvs (`vibe`, the agent
   loop, and `mcp`, lean-lsp-mcp with its Lean 4.23 patches) into `.aiprover/nix/`. The virtualenvs
   are the packages `venv-vibe` and `venv-mcp` of `orchestration/flake.nix`, so both components
   use identical environments.
2. It writes the configuration `.aiprover/aiprover.toml`, in the format of
   `harness/AIProver_plugin/aiprover.toml`, and links `~/.config/aiprover/aiprover.toml` to it.
3. It runs `harness/AIProver_plugin/setup.sh lean`: elan, Lean v4.23.0, and the Mathlib project
   with the REPL and cslib at `.aiprover/lean_project`.
4. It runs `aiprover doctor`.
5. It installs the plugin `aiprover` from the marketplace `skill/`.

A later run without `--endpoint` keeps the existing configuration, which may also be edited
directly.

## Configuration

The CLI reads `$AIPROVER_CONFIG`, then the nearest `aiprover.toml` above the script, and then
`~/.config/aiprover/aiprover.toml`. The template `harness/AIProver_plugin/aiprover.toml` is the
nearest file to the script, so a call from the checkout needs `AIPROVER_CONFIG`. `nix develop`
sets it, and the installed plugin finds the configuration through the link in `~/.config/aiprover/`.

| Section | Contents |
| --- | --- |
| `[endpoint]` | `mode` (`direct` or `ssh`), `api_base`, `api_key`, or the SSH host, the remote address, an optional handoff file, and the local tunnel port (18565) |
| `[runtime]` | `work_root` (`.aiprover/work`), `timeout_sec`, `max_turns`, `max_parallel` |
| `[paths]` | `lean_project`, `elan_home`, `vibe_venv`, `mcp_venv`, `rg_dir` |
| `[helpers]` | the LLM that answers `expand`, `backtranslate`, and `ask` (default `auto`: the agent of the current mode) |

## Use

```bash
nix develop
aiprover doctor
aiprover submit --problem problem.txt -k 4 --name demo    # prints JOB
aiprover wait JOB --timeout 540                           # exit status 3: still running
aiprover result JOB
aiprover check .aiprover/work/jobs/JOB/s0.lean
```

The problem file holds `<informal_theorem>` and `<informal_proof>` blocks; an empty proof block
requests the statement only. In Claude Code, giving the same two blocks triggers the skill.

## Model server

`harness/AIProver_plugin/serve/serve_aiprover.sh /path/to/aiprover_model` starts vLLM with the
flags that the harness requires; `serve/serve_vista_pp2.slurm` serves on Slurm clusters with one
GPU per node. Any OpenAI-compatible server of the model is reachable through `--endpoint`.
