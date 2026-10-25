# pstack in Copilot CLI

pstack skills use Cursor names. In Copilot CLI, read this file once per session, then map each Cursor name with the tables. `<pstack>` means the folder that holds `skills/` and `docs/`. If a Cursor field has no row, drop it and say so. Never pass a field the tool schema rejects.

## Tools

| Cursor | Copilot CLI |
| --- | --- |
| `Task` | The CLI tool `task`. |
| `AskQuestion` | `ask_user`. |
| Open a todolist | The CLI docs name no todo tool. Keep the list in the reply and update it at each phase. |
| Run another pstack skill | Read `<pstack>/skills/<name>/SKILL.md` and follow it. The menu may show `pstack:<name>`. A skill-tool lookup of that joined name can return not found while the plugin is loaded. Read the file and continue. VS Code documents `disable-model-invocation`. The CLI skill how-to does not. If a skill loads from ordinary wording, say so once. |

## Subagent fields

| Cursor | Copilot CLI |
| --- | --- |
| `subagent_type: generalPurpose` | The built-in `general-purpose`. |
| `poteto-agent`, `comment-sicko` | The profiles `com.github.copilot/agents/poteto-agent.agent.md` and `com.github.copilot/agents/comment-sicko.agent.md`. The name the CLI lists was not measured. Use the file name without `.agent.md` unless the session shows another name, and say which name you used. |
| `readonly: true` | `readonly` true is not a CLI flag. A Copilot CLI 1.0.103 work run reported a restricted explorer agent. Use that agent when the session lists it. The brief still says do not edit files, and you check `git status` afterward. |
| `readonly: false` | `general-purpose`. Whether it sees the session MCP servers was not measured. If `why` cannot see MCP, say so and run only the git evidence and the forge command from the forge table. |
| `environment: "cloud"` | `git worktree add` on a named branch. Do not start the GitHub cloud coding agent from `task`. A `task` call has no documented way to start one. |
| `environment: "local"` | Omit. |
| `cloud_base_branch` | Tell the worker to check out that branch first. |
| `run_in_background` | Pass `mode=background`. Copilot CLI 1.0.103 on a work machine returned from three such calls while the parent continued. Omit `mode` when the parent must wait for the child. The CLI default is 32 concurrent subagents and nesting depth 4, documented at https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/speed-up-task-completion. |
| `resume` | Spawn a new agent and paste the earlier result into the brief. `write_agent` is only for a child that still holds a checkout or a running process. |
| `file_attachments` | List the paths in the brief. |
| `include-custom-instructions` | CLI subagents skip repository instruction files unless `include-custom-instructions` is true, documented at https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference. The profiles set `include-custom-instructions` to true. |

## Models

| Cursor | Copilot CLI |
| --- | --- |
| `model` on `task` | Pass `model` only when the task tool accepts that slug. A session model is not automatically a task model. The 1.0.103 work run reported no Grok entry in the task model list. If the tool rejects the slug, omit `model` and say so. |
| Reasoning budget | The 1.0.103 work run reported `reasoning_effort` and `context_tier` as task fields. Pass `reasoning_effort` for the role budget when the tool accepts it. |
| `/subagents` | The 1.0.103 work run reported per-agent model preferences. Those preferences can override an omitted `model`. Omitting `model` does not prove the child uses the session model. |
| Session model is Auto | If the session model is Auto, subagents ignore the `model` field on a profile, documented at https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference. |
| `auto` or `inherit-parent` | Omit `model`. |
| Two model families | `interrogate` needs two families. If the task tool can accept only one, write `Skipped in Copilot CLI: interrogate diversity. The task tool accepted one model family.` Do not treat one model as a panel. |
| `~/.cursor/rules/pstack-models.mdc` | There is no file the CLI loads in place of `~/.cursor/rules/pstack-models.mdc`. Do not write that Cursor path from a Copilot session. A named session model does not assign roles. |

## setup-pstack

Do not run `/setup-pstack` on Copilot CLI. Those steps write `~/.cursor/rules/pstack-models.mdc` and call `AskQuestion`. Write `Skipped in Copilot CLI: /setup-pstack. Role models are passed on task when the tool accepts them.`

## Paths

| Cursor | Copilot CLI |
| --- | --- |
| `.cursor/skills`, `~/.cursor/skills` | For a verification skill written from a Copilot session, use `.github/skills/verify-<app>/`. Copilot CLI 1.0.98 on the build machine listed a skill placed in that folder. |
| `~/.cursor/plugins` | Copilot files for this plugin live in `com.github.copilot/`, documented at https://docs.github.com/en/copilot/concepts/customizations/plugins. Skills stay in `skills/`. The root `plugin.json` already uses the Agent Plugins 1.0 schema, `https://agent-plugins.org/schemas/1.0.0/plugin.schema.json`. Do not add a `skills` field. |
| Transcripts in `~/.cursor/projects/<slug>/agent-transcripts` | CLI 1.0.98 on the build machine wrote sessions under `~/.copilot/session-state/<session-id>/`. The 1.0.103 work run reported native session history. Read that session directory when a step needs a transcript. `skills/poteto-mode/scripts/worktree-audit.sh` looks there as well as under the Cursor transcript path. |
| Agent store | Pass `--store` or `ORCH_STORE`. Use a folder the session can write, and say which one. |

## Cursor-only features

For a missing convenience, write `Skipped in Copilot CLI: <step>. <reason>.`, then continue. A shipping proof is not a convenience. If that proof cannot be produced, write the skip line and leave the gate blocked.

| Cursor | Copilot CLI |
| --- | --- |
| Cursor Automations, `make-bot-ui`, and the automations pack | Skip. This repo does not ship `automations/`. |
| Bugbot startup, waits, and configuration | Skip. Existing Bugbot comments are ordinary review threads. Use the forge command from the forge table. That is not a skip. |
| Cursor cloud agents and the Cursor dashboard | The worktree row covers `environment` cloud. Skip a step that needs the Cursor cloud machine. |
| Custom Mode | Skip. Nothing holds `/poteto-mode` across turns. Ask for poteto-mode again when the chat drifts. |
| `/loop` | Skip the execution. Plan files may keep the word so `skills/poteto-mode/scripts/check-plan.mjs` still passes. A plan that names `/loop` is not supervised until a timer is actually armed. |
| `cursor-team-kit` skills `/deslop`, `control-ui`, and `control-cli` | Skip. They are not in this package. |
| `/create-skill` and `/add-plugin` | Write `SKILL.md` directly. Install with `copilot plugin install`. Not a skip. |
| A built-in PR tool | Use the forge named by the `origin` remote. Read the forge table before you run a playbook `gh pr` command. |

## Forge commands

Read `git remote get-url origin` before the first forge command. A URL that contains `gitlab` is GitLab. Any other URL stays on the playbook `gh` command.

On GitLab, use the command in the row. These flags come from the GitLab CLI docs fetched 25 October 2026. `glab` was not installed on the machine that wrote this note, so the commands were not run here.

| Playbook command | GitLab command |
| --- | --- |
| `gh pr create --base <branch>` | `glab mr create --target-branch <branch>` |
| `gh pr view <id>` | `glab mr view <id>` |
| `gh pr merge <id>` | `glab mr merge <id>` |
| `gh pr edit <id> --base <branch>` | `glab mr update <id> --target-branch <branch>` |
| `gh pr ready <id>` | `glab mr update <id> --ready` |
| `gh pr list` | `glab mr list --all --per-page 100 --output json` |
| `gh pr checks` | `glab ci status` |

`glab mr create` is documented at https://docs.gitlab.com/cli/mr/create/. `glab mr update` is documented at https://docs.gitlab.com/cli/mr/update/. `glab mr merge` is documented at https://docs.gitlab.com/cli/mr/merge/. `glab mr list` is documented at https://docs.gitlab.com/cli/mr/list/. `glab ci status` is documented at https://docs.gitlab.com/cli/ci/status/.

`skills/poteto-mode/scripts/watch-pr` queries GitHub. On GitLab, skip it. A missing watcher result does not clear a shipping gate. A missing `gh` binary returns a non-retryable watcher error.

`skills/poteto-mode/scripts/worktree-audit.sh` uses `glab mr list --all --per-page 100 --output json` when the origin URL contains `gitlab`. A closed request that is not merged is `review`. A merged request is `safe` when the worktree is clean and no recent chat touched it.

## Other Copilot surfaces

Docs fetched 25 October 2026.

VS Code Copilot has skills, one selected custom agent, a task tool, a todo tool, and an ask-user tool. Parallel fan-out is not documented for VS Code Copilot. VS Code ignores profile `mcp-servers`. `disable-model-invocation` is documented at https://code.visualstudio.com/docs/agent-customization/agent-skills. On the cloud coding agent, `ask_user` does not produce a useful result, and `todo` is not supported.

The GitHub cloud coding agent is one repository, one branch, one pull request, and a 59 minute stop, documented at https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent. The cloud agent docs disagree on subagents and on whether the profile `model` field applies. Do not use it as a swarm worker. Mission Control steers jobs and does not load a plugin by itself, documented at https://docs.github.com/en/copilot/how-tos/copilot-on-github/use-copilot-agents/manage-and-track-agents.

Do not add a hook file. Plugin hook cwd was not measured. A `sessionStart` prompt hook would submit a user turn in every session, so do not add one by guess.
