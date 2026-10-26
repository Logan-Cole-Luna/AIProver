# Claude Code plugins

`skill/` is the Claude Code marketplace `aiprover`. It lists the plugins of both components and
holds no plugin code: each entry of `plugins/` is a link into a submodule.

| Plugin | Skill | Source |
| --- | --- | --- |
| `aiprover` | `aiprover-autoformalize`, and the lean-lsp MCP server | `harness/AIProver_plugin/claude_code` |
| `aiprover-orchestration` | `aiprover-captain` | `orchestration/orchestration_plugin/claude_code` |

The setup commands install the plugins at user scope and replace earlier installs from the
per-repository marketplaces (`aiprover-local`, `aiprover-orchestration-local`). Without the setup:

```bash
claude plugin marketplace add "$PWD/skill"
claude plugin install aiprover@aiprover --scope user
claude plugin install aiprover-orchestration@aiprover --scope user
```

The installed plugins find their configuration through `~/.config/aiprover/` (harness) and
`~/.config/aiprover_orchestration/` (orchestration), which the setup links. After a submodule
bump, rerunning the setup reinstalls both plugins, and open sessions then need a restart.
