# AIProver orchestration

The orchestration ([Logan-Cole-Luna/aiprover-orchestration](https://github.com/Logan-Cole-Luna/aiprover-orchestration),
submodule `orchestration/`) directs AI agents at a mathematical problem in Lean 4. A captain
formalizes the problem, an auditor checks the formalization blind, the captain decomposes the
proof into lemmas, AIProver jobs prove the lemmas, and a reviewer and a writer check and
present the assembled result. A theorem library records what is formalized and proved, and a
query server exposes both over HTTP.

| Entry point | Location |
| --- | --- |
| Claude Code skill `aiprover-captain` (plugin `aiprover-orchestration`) | `orchestration/orchestration_plugin/` |
| Orchestrator, one run per problem | `python3 -m aiprover_orchestration.orchestrator` |
| Query server | `aiprover_orchestration/server/`, systemd units in `scripts/systemd/` |
| Theorem library | `python3 -m aiprover_orchestration.library` |

The orchestration's [README](orchestration/README.md) documents the pipeline, the
configuration, and the results.

## Setup

```bash
nix run .#setup-orchestration -- --endpoint http://<host>:<port>
```

The command runs `orchestration/setup --harness <this repository>/harness --no-plugin` with the
options given, and then installs the plugin `aiprover-orchestration` from the marketplace
`skill/`. `orchestration/setup` performs the following steps:

1. It builds the orchestration tools and the harness virtualenvs into `orchestration/aiprover/nix/`.
2. It writes `orchestration_plugin/endpoint.toml` (the model server) and
   `orchestration_plugin/aiprover.toml` (the harness, which reaches the server through the local
   reasoning proxy on port 18575).
3. It builds the Lean project and links the configuration into `~/.config/aiprover_orchestration/`.
4. It opens the connection and runs the doctor.

When the harness is set up first (`nix run .#setup`), the orchestration uses its Lean project,
`.aiprover/lean_project`. The orchestration accepts further options, such as `--endpoint dgx`,
`--endpoint vista`, and `--lean-project`; `orchestration/setup --help` lists them.

## Harness resolution

The orchestration locates the harness with one rule in `aiprover_orchestration/paths.py`,
`orchestration_plugin/setup.sh`, and the skill's `scripts/env.sh`. It uses `$AIPROVER_HARNESS`
when set, then the link `aiprover/harness`, and otherwise the `AIProver/` submodule.
`orchestration/setup --harness PATH` writes the link, and later runs keep it. The link lies
inside the checkout, so several checkouts on one machine may use different harnesses.

## Use

```bash
cd orchestration
python3 -m uvicorn aiprover_orchestration.server.app:app --host 127.0.0.1 --port 8443 --workers 1
```

The query server is then at http://127.0.0.1:8443/dev. In Claude Code, the request
"Use the aiprover-captain skill to formalize and prove <uuid of data/*.jsonl>" starts a run; so
do `<informal_theorem>` and `<informal_proof>` blocks. Each run is recorded in
`orchestration/results/<run_id>/`.
