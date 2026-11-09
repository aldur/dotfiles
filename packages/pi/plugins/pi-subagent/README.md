# Subagent extension

[index.ts](index.ts) and [agents.ts](agents.ts) are based on the
[Pi v1.4.0 subagent example](https://github.com/earendil-works/pi/tree/v1.4.0/packages/coding-agent/examples/extensions/subagent).
The upstream [MIT license](LICENSE) applies.

The source is stored here. Pi package updates do not replace it. Review upstream
changes before you apply them. The build runs
[the extension tests](../../tests/plugins/pi-subagent.mjs) with the packaged Pi.

## Differences from upstream v1.4.0

- **Agent files:** Upstream loads agents from user and project directories.
  This copy also accepts repeated `--agent <file.md>` options, lists those agents
  in the tool description, and passes their absolute paths to child processes.
  CLI definitions take precedence over directory definitions.
- **Model selection:** Upstream selects the frontmatter model, then the parent
  model. This copy adds a `model` field to the tool call and to each parallel task
  or chain step. These fields take precedence over frontmatter. An explicit
  model does not inherit the parent thinking level.
- **Sessions:** Upstream starts children with `--no-session`. This copy creates
  a separate session for each child, records the parent session path, and sets
  the name to `subagent:<name>`. It does not copy parent messages.
- **Extensions:** Upstream can start the current Pi script directly. This copy
  also passes the paths in `DOTFILES_PI_EXTENSIONS` as `-e` options, so children
  use the same plugin builds as the parent wrapper.
- **Rate limits:** Worker starts are at least 1.5 seconds apart within each
  parent process. After a 429 or rate limit error, the worker adds a delay before
  its next request: 10, 20, 40, then at most 60 seconds. Pi keeps its retry limit
  and adds its own delay. A successful response resets the added delay.
  Cancellation stops the wait. Parent requests keep their usual retry policy.

## Agent files

Use one `--agent` option for each Markdown file:

```sh
pi --agent ./agents/scout.md --agent ./agents/worker.md
```

Each file must have `name` and `description` strings in its YAML frontmatter.
Optional `model` and `tools` fields set the agent defaults. The Markdown body
supplies the agent instructions.

```markdown
---
name: scout
description: Find relevant code
tools: [read, bash]
model: provider/model-id
---
Find the code needed for the task. Report file paths and line numbers.
```

Paths are relative to the directory where Pi starts. `--agent=path` also works.
CLI agents are available in all agent scopes. They replace directory agents
with the same name. If CLI files have the same name, the last file wins.
Child processes receive the same absolute paths for nested calls.

## Model overrides

Set `model` in a `subagent` tool call:

```json
{"agent": "scout", "task": "Find the parser", "model": "provider/model-id"}
```

For parallel or chain calls, set `model` on the call, on each item in `tasks`
or `chain`, or both. Selection order:

1. Task or chain item `model`.
2. Tool call `model`.
3. Agent frontmatter `model`.
4. Parent session model.

The parent thinking level is used only when the parent model is inherited.
Each child has a separate session linked to its parent session. Child processes
also use the extension paths from the Pi wrapper.
