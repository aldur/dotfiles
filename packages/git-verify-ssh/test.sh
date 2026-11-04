#!/usr/bin/env bash
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL="$work/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

fail() {
  if git-verify-ssh "$@" >"$work/output" 2>&1; then
    cat "$work/output"
    echo 'Expected verification to fail.' >&2
    exit 1
  fi
}

for name in trusted other; do
  ssh-keygen -q -t ed25519 -N '' -f "$work/$name"
  printf 'test namespaces="git" %s\n' "$(cat "$work/$name.pub")" > "$work/$name.signers"
done
git config --global user.name Test
git config --global user.email test@example.com
git config --global gpg.format ssh
git config --global user.signingKey "$work/trusted"
git config --global commit.gpgSign true
git config --global init.defaultBranch main
git config --global core.hooksPath /dev/null
git init -q "$work/repo"
cd "$work/repo"
git commit -q --allow-empty -m trusted
root=$(git rev-parse HEAD)

fail .
git config --global gpg.ssh.allowedSignersFile "$work/trusted.signers"
git-verify-ssh . > "$work/output" 2>&1
grep -F '✓ Verified 1/1 commits' "$work/output"
if grep -Eq $'Good "git"|Checking 1/|\033' "$work/output"; then
  echo 'Unexpected signature details or terminal output.' >&2
  exit 1
fi
git commit -q --allow-empty -m second
git-verify-ssh
git-verify-ssh --allow-github .
git clone -q --bare . "$work/bare"
git-verify-ssh "$work/bare"

git switch -q -c unsigned "$root"
git -c commit.gpgSign=false commit -q --allow-empty -m unsigned
unsigned=$(git rev-parse HEAD)
fail .
grep -F "$unsigned" "$work/output"
grep -F 'Subject: unsigned' "$work/output"
grep -F 'No verifiable SSH signature.' "$work/output"
fail --allow-github .
git replace "$unsigned" "$root"
fail .
git replace -d "$unsigned"
git commit -q --allow-empty -m 'signed descendant'
fail .
git switch -q main
git-verify-ssh .
git switch -q -c merged
git merge -q --no-ff unsigned -m merged
fail .
git switch -q main
git branch -D merged
git branch -D unsigned
git update-ref refs/remotes/origin/unsigned "$unsigned"
git-verify-ssh .
git update-ref -d refs/remotes/origin/unsigned
git tag unsigned "$unsigned"
git-verify-ssh .
git tag -d unsigned
git switch -q --detach "$unsigned"
fail .
git switch -q main

printf 'stashed\n' > stashed
git add stashed
git stash push -q
git-verify-ssh .

git switch -q -c other "$root"
git -c user.signingKey="$work/other" commit -q --allow-empty -m other
git config gpg.ssh.allowedSignersFile "$work/other.signers"
fail .
fail --allow-github .
git config gpg.ssh.program true
fail .
git config --unset gpg.ssh.program
git switch -q main
git branch -D other
git-verify-ssh .

git replace "$root" "$unsigned"
git-verify-ssh .
git replace -d "$root"

git cat-file commit "$root" > "$work/commit"
printf '\nchanged\n' >> "$work/commit"
tampered=$(git hash-object -t commit -w "$work/commit")
git update-ref refs/heads/tampered "$tampered"
git switch -q tampered
fail .
fail --allow-github .
git switch -q main
git branch -D tampered

export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Test <test@example.com>' ed25519 sign 0
git switch -q -c openpgp
git -c gpg.format=openpgp -c user.signingKey=test@example.com \
  commit -q --allow-empty -m openpgp
git verify-commit HEAD
fail .
fail --allow-github .
git switch -q main
git branch -D openpgp
gpgconf --kill gpg-agent

# Verify a real GitHub signature without fetching history or changing HEAD.
github_commit=$(git hash-object -t commit -w "$GITHUB_COMMIT")
git -c gpg.openpgp.program="$GITHUB_VERIFIER" -c gpg.minTrustLevel=undefined \
  verify-commit "$github_commit"
cat "$GITHUB_COMMIT" > "$work/github-commit"
printf '\nchanged\n' >> "$work/github-commit"
github_tampered=$(git hash-object -t commit -w "$work/github-commit")
if git -c gpg.openpgp.program="$GITHUB_VERIFIER" -c gpg.minTrustLevel=undefined \
  verify-commit "$github_tampered"; then
  echo 'Accepted an altered GitHub commit.' >&2
  exit 1
fi

git clone -q --depth=1 "file://$work/repo" "$work/shallow"
fail "$work/shallow"
printf '%s\n' "$(git rev-parse HEAD)" > .git/info/grafts
fail "$work/repo"
rm .git/info/grafts

git init -q "$work/empty"
fail "$work/empty"
fail "$work/missing"
echo 'SSH verification tests passed.'
