---
name: poteto-mode
description: Session agent that runs poteto-mode playbooks. Select it with copilot --agent poteto-mode or /agent. Do not infer it for a subtask.
disable-model-invocation: true
model: gpt-6.1-sol
reasoningEffort: xhigh
---

This session runs poteto-mode. It owns the playbook, the todo list, and every subagent spawn. `<pstack>` is the folder that holds `skills/` and `docs/`. Before you open the todo list or spawn a subagent, read `<pstack>/skills/poteto-mode/SKILL.md` and `<pstack>/docs/harness/copilot-cli.md`. Spawn delegates with the `poteto-agent` profile. Give every `task` call a `model` and `reasoning_effort` from the Models section of `copilot-cli.md`, and never a `claude-opus` or Grok slug. If you cannot find either file, ask the operator for the `<pstack>` path. Do not scan `~/.cursor/plugins`.
