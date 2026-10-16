---
name: github-ci
description: Create, edit, or review GitHub Actions workflows.
---

# GitHub CI

Follow the repository's CI conventions and preserve the intended triggers,
permissions, and job behavior while making the requested changes.
For a review-only request, report required changes and findings without editing.

## Action versions and pins

Use the latest stable version of every external action referenced by the
workflows and local actions being worked on, including reusable workflows and
action subpaths. Check upstream releases, tags, and migration notes at the time
of the change; do not rely on memory or assume an existing pin is current.
Apply required input, output, runtime, and runner changes when upgrading majors.

Pin each external GitHub reference to its full 40-character commit SHA, with
the verified release version in a trailing comment. Resolve annotated tags to
the commit they point to, and verify the commit belongs to the upstream
repository. Do not use a tag, branch, shortened SHA, or tag-object SHA as the pin.
Keep references to the same action consistent across the files in scope.

Local `./...` actions and workflows use the current checkout and retain their
local references. Pin `docker://` actions to an immutable `sha256` image digest
for the latest stable version. If an upstream has no stable release or tag,
inspect its documented release policy and report that limitation rather than
inventing a version or silently retaining an old one.

## Require a clean zizmor audit

Use a current zizmor release supporting the following flags. From the repository
root, audit all workflows and action definitions:

```sh
zizmor --persona=auditor --no-ignores --strict-collection .
```

Run online audits with available GitHub authentication as described in
[zizmor's usage guide](https://docs.zizmor.sh/usage/#operating-modes).
An offline or partially skipped audit does not satisfy the full check.

Fix findings and rerun until the final audit completes successfully with zero
findings at every severity, including informational findings. Review automatic
fixes and rerun without fix mode for the final verification.

Do not add ignore comments, exclude inputs, disable rules, raise severity or
confidence thresholds, use `--no-exit-codes`, or otherwise suppress findings to
make the audit pass. Do not treat a successful SARIF export as a clean audit.
Keep required CI behavior intact when resolving findings.

Run the repository's other relevant workflow checks as well. Report the final
audit command and result. If tooling, authentication, an upstream incompatibility,
or a finding prevents completion, identify what remains unresolved and do not
claim the CI is clean.
