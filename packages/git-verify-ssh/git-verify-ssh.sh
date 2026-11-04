#!/usr/bin/env bash
set -euo pipefail

allow_github=false
if [[ ${1:-} == --allow-github ]]; then
  allow_github=true
  shift
fi

if [[ ${1:-} == --help ]]; then
  cat <<'EOF'
Usage: git-verify-ssh [--allow-github] [REPOSITORY]

Verify SSH signatures on all commits reachable from HEAD (the current branch).
Use keys in the global Git gpg.ssh.allowedSignersFile setting.
With --allow-github, also accept GitHub's pinned GPG signing keys.
This trusts GitHub-created commits, including Dependabot and web merges.
Run in the current directory if REPOSITORY is omitted.
This includes merged history. In detached HEAD mode, start at that commit.
No fetch is done. Tag signatures are excluded.
Exit with status 1 if verification fails or history is shallow.
EOF
  exit 0
fi
if (( $# > 1 )); then
  echo 'Usage: git-verify-ssh [--allow-github] [REPOSITORY]' >&2
  exit 1
fi

if ! signers=$(git config --global --includes --path --get gpg.ssh.allowedSignersFile) || [[ ! -r $signers ]]; then
  echo 'Set global Git gpg.ssh.allowedSignersFile to a readable file with your SSH keys.' >&2
  exit 1
fi
signers=$(realpath "$signers")

# Keep repository settings from changing the keys or verification programs.
git_cmd=(git --no-replace-objects -C "${1:-.}"
  -c "gpg.ssh.allowedSignersFile=$signers"
  -c gpg.ssh.program=ssh-keygen
  -c gpg.openpgp.program=false
  -c gpg.x509.program=false
  -c gpg.minTrustLevel=fully)
signature_scope=SSH
if "$allow_github"; then
  signature_scope='SSH or GitHub'
fi

if [[ $("${git_cmd[@]}" rev-parse --is-shallow-repository) == true ]]; then
  echo 'Cannot verify all history in a shallow repository.' >&2
  exit 1
fi
if [[ -s $("${git_cmd[@]}" rev-parse --path-format=absolute --git-path info/grafts) ]]; then
  echo 'Remove info/grafts before verification.' >&2
  exit 1
fi

commits=$("${git_cmd[@]}" rev-list HEAD)
mapfile -t commit_ids <<< "$commits"
total=${#commit_ids[@]}
branch=$("${git_cmd[@]}" symbolic-ref --quiet --short HEAD || "${git_cmd[@]}" rev-parse --short HEAD)
interactive=false
green='' red='' reset=''
if [[ -t 2 && ${TERM:-} != dumb ]]; then
  interactive=true
  if [[ -z ${NO_COLOR:-} ]]; then
    green=$'\033[32m' red=$'\033[31m' reset=$'\033[0m'
  fi
fi

printf 'Checking %s signatures on %s (%d commits)\n' "$signature_scope" "$branch" "$total" >&2
count=0
for commit in "${commit_ids[@]}"; do
  if "$interactive"; then
    printf '\r\033[K  Checking %d/%d' "$((count + 1))" "$total" >&2
  fi
  verified=false
  if details=$("${git_cmd[@]}" verify-commit "$commit" 2>&1); then
    verified=true
  elif "$allow_github"; then
    # The pinned keyring supplies GPG trust. Keep this separate from SSH trust.
    if github_details=$("${git_cmd[@]}" -c "gpg.openpgp.program=$github_verifier" \
      -c gpg.ssh.program=false -c gpg.minTrustLevel=undefined verify-commit "$commit" 2>&1); then
      verified=true
    else
      details="${details}${details:+$'\n'}${github_details}"
    fi
  fi
  if ! "$verified"; then
    if "$interactive"; then printf '\r\033[K' >&2; fi
    subject=$("${git_cmd[@]}" show --no-patch --no-show-signature --format=%s "$commit")
    commit_date=$("${git_cmd[@]}" show --no-patch --no-show-signature --format=%cI "$commit")
    printf '%s✗ Verification failed%s\n' "$red" "$reset" >&2
    printf '  Commit:  %s\n  Subject: %s\n  Date:    %s\n' "$commit" "$subject" "$commit_date" >&2
    printf '  Verified %d/%d commits before stopping.\n\n' "$count" "$total" >&2
    printf '%s\n' "${details:-No verifiable $signature_scope signature.}" >&2
    exit 1
  fi
  count=$((count + 1))
done
if "$interactive"; then printf '\r\033[K' >&2; fi
printf '%s✓ Verified %d/%d commits%s — all signatures are trusted.\n' "$green" "$count" "$total" "$reset" >&2
