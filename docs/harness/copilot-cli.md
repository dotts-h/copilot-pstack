# pstack in Copilot CLI

pstack skills use Cursor names. In Copilot CLI, read this file once per session, then map each Cursor name with the tables. `<pstack>` means the folder that holds `skills/` and `docs/`. If a Cursor field has no row, drop it and say so. Never pass a field the tool schema rejects.

## Tools

| Cursor | Copilot CLI |
| --- | --- |
| `Task` | The CLI tool `task`. |
| `AskQuestion` | `ask_user`. |
| Open a todolist | The CLI docs name no todo tool. Keep the list in the reply and update it at each phase. |
| Run another pstack skill | Read `<pstack>/skills/<name>/SKILL.md` and follow it. Do not assume a slash name loads it. VS Code documents `disable-model-invocation`. The CLI skill how-to does not. If a skill loads from ordinary wording, say so once. |

## Subagent fields

| Cursor | Copilot CLI |
| --- | --- |
| `subagent_type: generalPurpose` | The built-in `general-purpose`. |
| `poteto-agent`, `comment-sicko` | The profiles `com.github.copilot/agents/poteto-agent.agent.md` and `com.github.copilot/agents/comment-sicko.agent.md`. The name the CLI lists was not measured. Use the file name without `.agent.md` unless the session shows another name, and say which name you used. |
| `readonly: true` | `readonly` true is not a CLI flag. The brief says do not edit files, and you check `git status` afterward. The built-in `explore` agent is documented as safe to run in parallel. The docs do not call it read-only. Use `explore` for parallel read-only explorers, and still add the brief and the `git status` check. |
| `readonly: false` | `general-purpose`. Whether it sees the session MCP servers was not measured. If `why` cannot see MCP, say so and run only the git and `gh` evidence. |
| `environment: "cloud"` | `git worktree add` on a named branch. Do not start the GitHub cloud coding agent from `task`. A `task` call has no documented way to start one. |
| `environment: "local"` | Omit. |
| `cloud_base_branch` | Tell the worker to check out that branch first. |
| `run_in_background` | Omit. Start every child of one step in the same turn. The CLI default is 32 concurrent subagents and nesting depth 4, documented at https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/speed-up-task-completion. Whether one `task` call blocks the parent was not measured. |
| `resume` | Spawn a new agent and paste the earlier result into the brief. `write_agent` is only for a child that still holds a checkout or a running process. |
| `file_attachments` | List the paths in the brief. |
| `include-custom-instructions` | CLI subagents skip repository instruction files unless `include-custom-instructions` is true, documented at https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference. The profiles set `include-custom-instructions` to true. |

## Models

| Cursor | Copilot CLI |
| --- | --- |
| `model` on `task` | Omit `model` on `task` so the child uses the session model, and say so once. |
| Session model is Auto | If the session model is Auto, subagents ignore the `model` field on a profile, documented at https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference. Do not write per-role profiles. |
| `auto` or `inherit-parent` | Omit `model`. |
| `~/.cursor/rules/pstack-models.mdc` | There is no file the CLI loads in place of `~/.cursor/rules/pstack-models.mdc`. Do not write that Cursor path from a Copilot session. |

## setup-pstack

Do not run the Cursor steps. They write `~/.cursor/rules/pstack-models.mdc` and call `AskQuestion`.

Until a named session model is in use, skip `/setup-pstack` on Copilot CLI and write `Skipped in Copilot CLI: /setup-pstack. Per-role profiles are a later change.`

## Paths

| Cursor | Copilot CLI |
| --- | --- |
| `.cursor/skills`, `~/.cursor/skills` | For a verification skill written from a Copilot session, use `.github/skills/verify-<app>/`. VS Code and the cloud agent document that repository folder. That the CLI reads it is inferred. |
| `~/.cursor/plugins` | Copilot files for this plugin live in `com.github.copilot/`, documented at https://docs.github.com/en/copilot/concepts/customizations/plugins. Skills stay in `skills/`. The root `plugin.json` already uses the Agent Plugins 1.0 schema, `https://agent-plugins.org/schemas/1.0.0/plugin.schema.json`. Do not add a `skills` field. |
| Transcripts in `~/.cursor/projects/<slug>/agent-transcripts` | No Copilot path was documented. Skip a step that needs them. `skills/poteto-mode/scripts/worktree-audit.sh` already prints `-` when that directory is missing. Do not edit that script. |
| Agent store | Pass `--store` or `ORCH_STORE`. Use a folder the session can write, and say which one. |

## Cursor-only features

For a skip, write `Skipped in Copilot CLI: <step>. <reason>.`, then continue.

| Cursor | Copilot CLI |
| --- | --- |
| Cursor Automations, `make-bot-ui`, and the automations pack | Skip. This repo does not ship `automations/`. |
| Bugbot startup, waits, and configuration | Skip. Existing Bugbot comments are ordinary review threads. Use the `gh` command the step gives. That is not a skip. |
| Cursor cloud agents and the Cursor dashboard | The worktree row covers `environment` cloud. Skip a step that needs the Cursor cloud machine. |
| Custom Mode | Skip. Nothing holds `/poteto-mode` across turns. Ask for poteto-mode again when the chat drifts. |
| `/loop` | Skip. Plan files keep `/loop` phrases so `skills/poteto-mode/scripts/check-plan.mjs` still passes. Do not edit `check-plan.mjs`. |
| `cursor-team-kit` skills `/deslop`, `control-ui`, and `control-cli` | Skip. They are not in this package. |
| `/create-skill` and `/add-plugin` | Write `SKILL.md` directly. Install with `copilot plugin install`. Not a skip. |
| A built-in PR tool | Use `gh pr create`. Not a skip. |

## Other Copilot surfaces

Docs fetched 25 October 2026.

VS Code Copilot has skills, one selected custom agent, a task tool, a todo tool, and an ask-user tool. Parallel fan-out is not documented for VS Code Copilot. VS Code ignores profile `mcp-servers`. `disable-model-invocation` is documented at https://code.visualstudio.com/docs/agent-customization/agent-skills. On the cloud coding agent, `ask_user` does not produce a useful result, and `todo` is not supported.

The GitHub cloud coding agent is one repository, one branch, one pull request, and a 59 minute stop, documented at https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent. The cloud agent docs disagree on subagents and on whether the profile `model` field applies. Do not use it as a swarm worker. Mission Control steers jobs and does not load a plugin by itself, documented at https://docs.github.com/en/copilot/how-tos/copilot-on-github/use-copilot-agents/manage-and-track-agents.

Do not add a hook file. Plugin hook cwd was not measured. A `sessionStart` prompt hook would submit a user turn in every session, so do not add one by guess.
