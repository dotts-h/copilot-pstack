# pstack in Copilot CLI

pstack skills use Cursor names. In Copilot CLI, read this file once per session, then map each Cursor name with the tables. `<pstack>` means the folder that holds `skills/` and `docs/`. If a Cursor field has no row, drop it and say so. Never pass a field the tool schema rejects.

Each fact about Copilot names its source. Measured means read from the Linux x64 package of Copilot CLI 1.0.98, or seen in a 1.0.98 session on the build machine. The offline run is one of those sessions. It set `COPILOT_OFFLINE=true` and answered from a local mock provider, so it shows nothing about which models GitHub offers. Docs means the linked page, fetched 25 October 2026 unless the sentence or its section gives another date. The operator's report means the operator saw it on their own machine, and this file did not re-run it. The 1.0.103 work run is one of those reports.

## Tools

| Cursor | Copilot CLI |
| --- | --- |
| `Task` | The CLI tool `task`. |
| `AskQuestion` | `ask_user`. |
| Open a todolist | Call `update_todo` with one `todos` string that holds a markdown checklist. If `update_todo` rejects the call, keep the list in the reply too. The tool and its one string argument were measured in the 1.0.98 `runtime.node`. Its description, measured in the same file, is "Use this TODO tool to manage the tasks that must be completed to solve the problem." The hooks reference lists `TodoWrite` as the Claude tool name for `update_todo`, documented at https://docs.github.com/en/copilot/reference/hooks-reference. |
| Run another pstack skill | Read `<pstack>/skills/<name>/SKILL.md` and follow it. The menu may show `pstack:<name>`. A skill-tool lookup of that joined name can return not found while the plugin is loaded. Read the file and continue. VS Code documents `disable-model-invocation`. The CLI skill how-to does not. If a skill loads from ordinary wording, say so once. |

## Subagent fields

| Cursor | Copilot CLI |
| --- | --- |
| `subagent_type: generalPurpose` | The built-in `general-purpose`. |
| `poteto-agent`, `comment-sicko` | The profiles `com.github.copilot/agents/poteto-agent.agent.md` and `com.github.copilot/agents/comment-sicko.agent.md`. In the offline run, the `task` tool's `agent_type` list named them `pstack:poteto-agent` and `pstack:comment-sicko`. Use the name the session's `task` tool lists, and say which name you used. |
| `readonly: true` | `readonly` true is not a CLI flag. A Copilot CLI 1.0.103 work run reported a restricted explorer agent. Use that agent when the session lists it. The brief still says do not edit files, and you check `git status` afterward. |
| `readonly: false` | `general-purpose`. Whether it sees the session MCP servers was not measured. If `why` cannot see MCP, say so and run only the git evidence and the forge command from the forge table. |
| `environment: "cloud"` | `git worktree add` on a named branch. Do not start the GitHub cloud coding agent from `task`. A `task` call has no documented way to start one. |
| `environment: "local"` | Omit. |
| `cloud_base_branch` | Tell the worker to check out that branch first. |
| `run_in_background` | Pass `mode=background`. Copilot CLI 1.0.103 on a work machine returned from three such calls while the parent continued. Omit `mode` when the parent must wait for the child. The CLI default is 32 concurrent subagents and nesting depth 4, documented at https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/speed-up-task-completion. |
| `resume` | Send the follow-up with `write_agent` and the child's `agent_id`. `write_agent` reaches only a running or idle background agent, measured in the 1.0.98 `runtime.node`. Start a child with `mode=background` when it may get a follow-up. The `read_agent` description, measured in the same file, says to keep using a known agent ID. A child that was retired after its turn cannot receive another message, and its delivered result stays readable with `read_agent`, measured in the same file. To continue that work, start a new agent and put the result in its brief. `copilot --resume` resumes a previous interactive session, documented at https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference, so it reopens the parent session and not a finished child. |
| `file_attachments` | List the paths in the brief. |
| `include-custom-instructions` | CLI subagents skip repository instruction files unless `include-custom-instructions` is true, documented at https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference. The `poteto-agent` and `comment-sicko` profiles set it to true. The `poteto-mode` profile leaves it out, because an agent you select with `--agent` or `/agent` already follows repository instructions, documented at https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents-for-cli. |

## Models

Docs fetched 26 October 2026.

The operator named the only models this Copilot install uses: Claude Sonnet 5.5, GPT-6.1 Sol, GPT-6 Luna, and Gemini 4. Never pass a `claude-opus` slug or a Grok slug. Only the two arena rows below pass `max`. Every other role runs at `xhigh` or lower, so when a skill says to raise effort up to `max`, stop at `xhigh`.

Start the session with `copilot --agent pstack:poteto-mode --model gpt-6.1-sol --reasoning-effort xhigh`. Do not run the session on Auto. The offline run sent `gpt-6.1-sol` at `xhigh` for that command. The `poteto-mode` profile also sets `model: gpt-6.1-sol` and `reasoning-effort: xhigh`. The command reference lists `model` and `reasoningEffort` in its custom agent frontmatter table, documented at https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference. In the offline run, CLI 1.0.98 logged `unknown field ignored: reasoningEffort` and applied `reasoning-effort`.

Pass `model` and `reasoning_effort` from the table below on every `task` call, built-in agents included. A built-in agent called without `model` runs on its own default, and those defaults are outside the operator's list. The 1.0.98 `explore` definition lists `gpt-5.6-luna`, then `gpt-5.4-mini`, with `reasoningEffort: low`, measured in the package's `definitions/explore.agent.yaml`. The command reference lists `claude-sonnet-4.6` as the `general-purpose` default and ranks an explicit per-call value above every other source of model and effort.

| Role | Model | Reasoning effort |
| --- | --- | --- |
| Session agent and orchestrator | `gpt-6.1-sol` | `xhigh` |
| `hardest tasks` | `gpt-6.1-sol` | `xhigh` |
| `interrogate reviewers` | `gpt-6.1-sol` and the slug the task tool shows for Gemini 4 Argon. If the tool shows no Gemini 4 slug, the second reviewer runs on `claude-sonnet-5.5`, and the verdict says so. | `xhigh` or lower |
| `arena runners` | One runner on `gpt-6.1-sol` and one on `claude-sonnet-5.5`. Extra runners reuse one of these two slugs. | `max` |
| `arena cross-judge pool` | `gpt-6.1-sol` and `claude-sonnet-5.5`. Pick the one whose family differs from the parent's, so a `gpt-6.1-sol` parent gets `claude-sonnet-5.5`. | `max` |
| Any other role the skills assign to Opus | `claude-sonnet-5.5` | `xhigh` or lower |
| Any other role the skills assign to Grok | `gpt-6-luna` | `xhigh` or lower |

The supported-models table at https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#supported-models lists `claude-sonnet-5.5`, `gpt-6.1-sol`, and `gpt-6-luna`. Its only Gemini slug is `gemini-3.8-flash`. The display name Gemini 4 Argon is documented at https://docs.github.com/en/copilot/reference/ai-models/supported-models. Do not guess a Gemini slug. The command reference lists `max` as a `--reasoning-effort` value and calls it the highest-depth tier for Anthropic models. The operator named `max` for both arena models anyway. If the task tool rejects `max` on `gpt-6.1-sol`, say so and run that runner at `xhigh`.

If the task tool rejects a slug from the table, run that role on another model from the operator's list. Name the rejected slug and the slug that ran. Do not fall back to a skill's default model, because those defaults are Opus and Grok.

| Cursor | Copilot CLI |
| --- | --- |
| `model` on `task` | Pass a slug the task tool accepts. The operator reported Claude, GPT, and Gemini models in their Copilot `task` tool. The 1.0.103 work run reported no Grok entry in the task model list. In the offline run, `model` and `reasoning_effort` were free strings with no list of values. Their descriptions say to pass a value only when the request or persistent instructions require it. This file and the `poteto-mode` profile require both on every call. |
| Reasoning budget | The 1.0.103 work run reported `reasoning_effort` and `context_tier` as task fields, and the offline run showed both. Pass `reasoning_effort` from the role table when the tool accepts it. |
| `/subagents` | The 1.0.103 work run reported per-agent model preferences. Those preferences can override an omitted `model`. The offline run's `task` schema says the runtime resolves `/subagents` preferences when `model` is omitted. Omitting `model` does not prove the child uses the session model. |
| Session model is Auto | If the session model is Auto, subagents ignore the `model` field on a profile, documented at https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference. |
| `auto` or `inherit-parent` | Pass `gpt-6.1-sol` at `xhigh`, the session's model and effort. Do not omit `model`. |
| Two model families | Run `interrogate` on the `interrogate reviewers` row above. In the verdict's Reviewers section, name the slug each reviewer ran on. If the tool accepts only one family, run every reviewer on that family and say that their agreement is weaker evidence than agreement across families. |
| `~/.cursor/rules/pstack-models.mdc` | There is no file the CLI loads in place of `~/.cursor/rules/pstack-models.mdc`. Do not write that Cursor path from a Copilot session. A named session model does not assign roles. The role table above does. |

## setup-pstack

Do not run `/setup-pstack` on Copilot CLI. Those steps write `~/.cursor/rules/pstack-models.mdc` and call `AskQuestion`. Write `Skipped in Copilot CLI: /setup-pstack. Role models are passed on task when the tool accepts them.`

## Paths

| Cursor | Copilot CLI |
| --- | --- |
| `.cursor/skills`, `~/.cursor/skills` | For a verification skill written from a Copilot session, use `.github/skills/verify-<app>/`. Copilot CLI 1.0.98 on the build machine listed a skill placed in that folder. |
| `~/.cursor/plugins` | Copilot files for this plugin live in `com.github.copilot/`, documented at https://docs.github.com/en/copilot/concepts/customizations/plugins. Skills stay in `skills/`. The root `plugin.json` already uses the Agent Plugins 1.0 schema, `https://agent-plugins.org/schemas/1.0.0/plugin.schema.json`. Do not add a `skills` field. |
| Transcripts in `~/.cursor/projects/<slug>/agent-transcripts` | CLI 1.0.98 on the build machine wrote sessions under `~/.copilot/session-state/<session-id>/`. The 1.0.103 work run reported native session history. Read that session directory when a step needs a transcript. `skills/poteto-mode/scripts/worktree-audit.sh` looks there as well as under the Cursor transcript path. |
| Agent store | Use the folder the operator named. If the operator named none, use `$HOME/.copilot/pstack-store` and name that path in the reply. Pass the folder to `skills/poteto-mode/scripts/orch/orch.ts` with `--store` or `ORCH_STORE`. `orch.ts` has no default and stops with `set --store <dir> or ORCH_STORE` when neither is set. Never use `~/.copilot/session-store.db` as the store. |

## Cursor-only features

For a missing convenience, write `Skipped in Copilot CLI: <step>. <reason>.`, then continue. A shipping proof is not a convenience. If that proof cannot be produced, write the skip line and leave the gate blocked.

| Cursor | Copilot CLI |
| --- | --- |
| Cursor Automations, `make-bot-ui`, and the automations pack | Skip. This repo does not ship `automations/`. |
| Bugbot startup, waits, and configuration | Skip. Existing Bugbot comments are ordinary review threads. Use the forge command from the forge table. That is not a skip. On GitHub, Copilot code review is requested on the pull request, documented at https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-code-review. `/review` runs the CLI's built-in code-review agent on local changes, documented at https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/agentic-code-review. Neither page describes a review of a GitLab merge request. |
| Cursor cloud agents and the Cursor dashboard | The worktree row covers `environment` cloud. Skip a step that needs the Cursor cloud machine. |
| Custom Mode | Start the session with `copilot --agent pstack:poteto-mode --model gpt-6.1-sol --reasoning-effort xhigh`, or pick the `poteto-mode` profile with `/agent` in an interactive session. Either one selects `com.github.copilot/agents/poteto-mode.agent.md` as the session agent, documented at https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents-for-cli. In the offline run, `--agent poteto-mode` stopped with `No such agent: poteto-mode, available: pstack:poteto-mode, pstack:comment-sicko, pstack:poteto-agent`. The 1.0.81 changelog entry gives the form `--agent <plugin>:<agent>`, measured in the 1.0.98 `changelog.json`. Pass the flags again for each new session. `poteto-agent` stays the child profile for playbook delegates. |
| `/loop` | In CLI 1.0.98, `/loop` is an alias of the experimental `/every` command, measured in the 1.0.98 `cli-main.js` and documented at https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/schedule-prompts. That page says experiments need `/experimental on` or `--experimental`. The page also says a schedule fires only while the interactive session that created it is running, and `--resume` restores the schedule. Writing `/loop` in a plan file does not arm a timer. If the session cannot arm `/loop`, a shipping gate that needs supervision stays blocked. `skills/poteto-mode/scripts/check-plan.mjs` fails a plan whose `## Program checklist` section lacks `/loop 1h`, so keep that phrase in plans. |
| `cursor-team-kit` skills `/deslop`, `control-ui`, and `control-cli` | Skip. They are not in this package. |
| `/create-skill` and `/add-plugin` | Write `SKILL.md` directly. Install with `copilot plugin install`. Not a skip. |
| A built-in PR tool | Use the forge named by the `origin` remote. Read the forge table before you run a playbook `gh pr` command. |

## Forge commands

Read `git remote get-url origin` before the first forge command, and take the host from that URL. A host that contains `gitlab`, such as `gitlab.com` or `gitlab.example.com`, is GitLab. Any other host stays on the playbook `gh` command. The path does not count, so `https://github.com/org/gitlab-tools` stays on GitHub. In an SSH remote such as `git@gitlab.com:group/repo.git`, the host is `gitlab.com`. A GitLab server whose host does not contain `gitlab`, such as `git.example.com`, also stays on `gh`. That case is unresolved.

On GitLab, use the command in the row. These flags come from the GitLab CLI docs fetched 25 October 2026, except where a citation below gives another date. `glab` was not installed on the machine that wrote this note, so the commands were not run here.

| Playbook command | GitLab command |
| --- | --- |
| `gh pr create --base <branch>` | `glab mr create --target-branch <branch>` |
| `gh pr view <id>` | `glab mr view <id>` |
| `gh pr view <id> --json state,mergedAt,baseRefName` | `glab mr view <id> --output json` |
| `gh pr merge <id>` | `glab mr merge <id>` |
| `gh pr edit <id> --base <branch>` | `glab mr update <id> --target-branch <branch>` |
| `gh pr ready <id>` | `glab mr update <id> --ready` |
| `gh pr list` | `glab mr list --all --per-page 100 --output json` |
| `gh pr checks <id>` | `glab ci get --merge-request <id>` |

`glab mr create` is documented at https://docs.gitlab.com/cli/mr/create/. `glab mr update` is documented at https://docs.gitlab.com/cli/mr/update/. `glab mr merge` is documented at https://docs.gitlab.com/cli/mr/merge/. `glab mr list` is documented at https://docs.gitlab.com/cli/mr/list/. `glab ci get` is documented at https://docs.gitlab.com/cli/ci/get/, fetched 26 October 2026. That page says its `--merge-request` flag takes the merge request IID and reads that request's head pipeline. Do not use bare `glab ci status` for checks, because it reads the current branch, documented at https://docs.gitlab.com/cli/ci/status/, fetched 26 October 2026.

For the shipping readback on GitLab, run `glab mr view <id> --output json`. The `glab mr view` page at https://docs.gitlab.com/cli/mr/view/, fetched 26 October 2026, lists `--output json` and names no JSON fields. Read that JSON once, then name the fields the readback used. Do not assume a `mergedAt` field.

`skills/poteto-mode/scripts/watch-pr` queries GitHub. On GitLab, skip it. A missing watcher result does not clear a shipping gate. A missing `gh` binary returns a non-retryable watcher error.

`skills/poteto-mode/scripts/worktree-audit.sh` lists GitLab merge requests with `glab mr list --all --per-page 100 --output json`. A closed request that is not merged is `review`. A merged request is `safe` when the worktree is clean and no recent chat touched it.

## Other Copilot surfaces

Docs fetched 25 October 2026.

VS Code Copilot has skills, one selected custom agent, a task tool, a todo tool, and an ask-user tool. Parallel fan-out is not documented for VS Code Copilot. VS Code ignores profile `mcp-servers`. `disable-model-invocation` is documented at https://code.visualstudio.com/docs/agent-customization/agent-skills. On the cloud coding agent, `ask_user` does not produce a useful result, and `todo` is not supported.

The GitHub cloud coding agent is one repository, one branch, one pull request, and a 59 minute stop, documented at https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent. The cloud agent docs disagree on subagents and on whether the profile `model` field applies. Do not use it as a swarm worker. Mission Control steers jobs and does not load a plugin by itself, documented at https://docs.github.com/en/copilot/how-tos/copilot-on-github/use-copilot-agents/manage-and-track-agents.

Do not add a hook file. A `sessionStart` prompt hook submits its text as a user turn in every new interactive session, documented at https://docs.github.com/en/copilot/reference/hooks-reference. Plugin hook cwd was not measured.
