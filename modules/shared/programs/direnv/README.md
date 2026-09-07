# Direnv

Home Manager and NixOS share the [stdlib](stdlib.nix) and
[settings](default.nix). This policy applies to ordinary host shells too.

Global direnv configuration checks tracked `*.nix`, `*.sh`, `flake.lock` and
`.envrc*` files across its Git repository, including initialized submodules,
before executing `.envrc`. This covers parent flakes and sibling imports.
Existing files can stay as simple as:

```sh
use flake
```

Other source/data edits do not trigger reapproval or per-file timestamp checks.
Cost scales with selected files across the repository; unrelated matching files
also need approval. Pending approvals still rehash that set.
Entry through subdirectories works too. Extend the patterns in
[the shared config](stdlib.nix) for common inputs.
Other formats, untracked inputs and non-Git projects need explicit declarations,
such as `require_allowed environment.json` before use. External inputs are
outside the automatic rule.
Review changes before `direnv allow`. Initial setup approves `.envrc`,
then its inputs. Missing selected files block loading until restored or
their reviewed removal is staged.
Approval does not freeze files; stop writers before host execution.
This uses upstream [`require_allowed`](https://github.com/direnv/direnv/pull/1530),
[backported](../../../../overlays/overrides/direnv.nix) until the next direnv release,
with checker errors made fatal and parent-relative inputs supported.
Approvals remain tied to the active `.envrc`.

All storage using `direnv_layout_dir` lives under
`${XDG_DATA_HOME:-~/.local/share}/direnv/layouts/<project-path-hash>`, outside
worktrees. This includes nix-direnv's cached environments, profiles, GC roots
and reload helper, plus the standard Python, Go, Perl and Ruby layout storage.
It applies globally after applying the configuration, including outside the
agent sandbox. Different worktrees have separate directories.

The [shared persistence list](../../preservation-paths.nix) already preserves
`~/.local/share/direnv`, including approvals and layout caches, under `/persist`.
A custom `XDG_DATA_HOME` needs a corresponding persistence entry.

Existing project `.direnv` directories are ignored; environments rebuild in
the new location. Old executable caches are not imported. This does not move
package-manager directories such as `node_modules` or a separately managed
`.venv`, nor paths explicitly overridden by `.envrc`.
Custom cache paths and uncovered inputs remain the project's responsibility.
