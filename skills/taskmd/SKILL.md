---
name: taskmd
description: Read and edit taskmd Markdown task files.
---

# taskmd

Follow the project's task directory, `.taskmd.yaml`, and existing task conventions.
Create or update tasks when requested or required by the project's instructions.
Do not introduce task tracking for unrelated work.

Each task is a Markdown file with YAML frontmatter and a free-form Markdown body:

```markdown
---
id: "001"
title: "Fix login button alignment"
status: pending
---

Describe the work and its acceptance criteria here.
```

`id` and `title` are required. Keep IDs unique and quote IDs and dependency IDs
as strings. Status values are `pending`, `in-progress`, `completed`, `in-review`,
`blocked`, and `cancelled`. Preserve existing metadata when editing.

Read the project's `TASKMD_SPEC.md`, or run `taskmd spec --stdout` for the full
syntax supported by the installed version. Use this for optional fields rather
than guessing their names or values. Do not run `taskmd init` just to learn the
format; it creates project and agent configuration files.

Edit task Markdown directly. The CLI is optional for editing; `taskmd --help`
and command-specific `--help` describe available operations. When taskmd is
available, run `taskmd validate --task-dir <task-directory>` after task changes.
