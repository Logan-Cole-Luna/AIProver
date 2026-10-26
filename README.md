# AIProver

<p align="center">
  <a href="https://arxiv.org/abs/2610.05367"><img alt="Paper" src="https://img.shields.io/badge/Paper-arXiv%3A2610.05367-b31b1b.svg"></a>
  <a href="https://jprithwish.github.io/AIProver/"><img alt="Project page" src="https://img.shields.io/badge/Project-Page-1f6feb.svg"></a>
  <a href="https://huggingface.co/prithwish-jana/aiprover-119b"><img alt="Model" src="https://img.shields.io/badge/%F0%9F%A4%97%20Hugging%20Face-aiprover--119b-ffcc4d.svg"></a>
</p>

AIProver auto-formalizes a natural-language theorem and its proof into a Lean 4 file that
compiles, contains no `sorry`, states exactly that theorem, and follows that proof. The prover is
a fine-tuned Leanstral-class model driven by an evolved agentic harness (Lean v4.23.0, Mathlib,
cslib, and the lean-lsp tools). The orchestration builds on it: Claude roles formalize a problem,
audit the formalization, decompose the proof into lemmas, and assign each lemma to AIProver jobs.

This repository is the single entry point to that software: it contains each component as a
submodule at a tested commit and sets the components up with Nix.

| Component | Path | Documentation |
| --- | --- | --- |
| Harness | `harness/` | [HARNESS.md](HARNESS.md) |
| Orchestration | `orchestration/` | [ORCHESTRATION.md](ORCHESTRATION.md) |
| Claude Code plugins | `skill/` | [skill/README.md](skill/README.md) |

```mermaid
flowchart LR
    U[User] --> C[Claude Code]
    C -->|aiprover-autoformalize| H[Harness<br/>harness/]
    C -->|aiprover-captain| O[Orchestration<br/>orchestration/]
    O -->|lemma jobs| H
    H -->|inference| M[AIProver model<br/>GPU server]
    H --> L[Lean project<br/>.aiprover/lean_project]
    O --> L
```

## Setup

Linux, WSL2, or macOS, with about 15 GB of free disk. Each command builds the environment and
the Lean project, connects the model server, and installs the Claude Code plugins.

```bash
git clone https://github.com/Logan-Cole-Luna/AIProver && cd AIProver
nix run .#setup-harness       -- --endpoint http://<host>:<port>   # the harness alone
nix run .#setup-orchestration -- --endpoint http://<host>:<port>   # the orchestration
nix run .#setup               -- --endpoint http://<host>:<port>   # both
```

On a machine without Nix, `scripts/setup.sh harness|orchestration|all` runs the same steps and
first installs Nix after confirmation (sudo once, to create `/nix`). The setup initializes the
submodules that it needs, so a plain clone suffices. `--dry-run` prints every step without
changing anything, and `--help` lists the options.

| Model server | Options | Connection |
| --- | --- | --- |
| none | `--endpoint none` | no model server; in the orchestration, Claude subagents prove the lemmas |
| reachable from the device | `--endpoint URL [--api-key KEY]` | direct |
| reachable only from an SSH host | `--endpoint URL --via HOST [--user USER]` | SSH tunnel through `HOST` |
| a scheduled job that writes `node=<n> port=<p>` to a file | `--via HOST --handoff FILE` | SSH tunnel to the node that the file names |

`nix develop` (or `direnv allow`, once) opens a shell with the tools of both components, the
`aiprover` CLI on `PATH`, and `AIPROVER_CONFIG` set to the harness configuration of the setup.
Then, in Claude Code, `<informal_theorem>` and `<informal_proof>` blocks start the
`aiprover-autoformalize` skill, and "Use the aiprover-captain skill to formalize and prove …"
starts an orchestration run. [HARNESS.md](HARNESS.md) and [ORCHESTRATION.md](ORCHESTRATION.md)
describe each component, its setup, and its use in full.

## Layout

```
├── README.md, HARNESS.md, ORCHESTRATION.md
├── flake.nix, flake.lock    # setup apps, harness tools, development shell
├── nix/harness-tools.nix    # programs of the harness and its setup
├── scripts/
│   ├── setup.sh             # the setup commands
│   └── check-pins.sh        # submodule commits and their consistency
├── skill/                   # Claude Code marketplace "aiprover" of both plugins
├── harness/                 # submodule: AIProver harness, CLI, and skill
├── orchestration/           # submodule: aiprover-orchestration
└── .aiprover/               # written by the setup: configuration, environments, Lean project, jobs
```
