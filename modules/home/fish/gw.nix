{ pkgs }: {
  description = "Create or switch to a git worktree for a (new) branch";
  body = ''
    argparse 'h/help' 'no-fetch' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: gw [--no-fetch] <branch> [base-ref]"
        return 0
    end

    if test (count $argv) -eq 0
        echo "Usage: gw [--no-fetch] <branch> [base-ref]"
        return 1
    end

    set -l branch $argv[1]

    # Tab-completion offers remote-tracking branches (origin/foo). Strip
    # the remote prefix so we create/switch a LOCAL branch `foo` that
    # tracks the remote, not a local branch literally named `origin/foo`.
    for remote in (git remote)
        if string match -q -- "$remote/*" $branch
            set branch (string replace -- "$remote/" "" $branch)
            break
        end
    end

    git check-ref-format --branch "$branch" >/dev/null
    or return 1

    set -l base
    if test (count $argv) -ge 2
        set base $argv[2]
    else
        set base (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)
    end

    set -l root (git rev-parse --show-toplevel) || return 1

    if not set -q _flag_no_fetch
        if not git fetch origin 2>/dev/null
            echo "gw: warning: fetch failed, continuing with local state" >&2
        end
    end

    # Already checked out elsewhere? Exact-match the branch ref in
    # porcelain output with awk (no regex, so dots or other metachars in
    # branch names can't cause false matches).
    set -l existing_wt (git worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree / { wt = substr($0, 10) } $0 == "branch " b { print wt; exit }')
    if test -n "$existing_wt"
        echo "gw: branch '$branch' already checked out at $existing_wt" >&2
        cd $existing_wt
        return
    end

    # A hash distinguishes slash/dash and case-only branch names.
    # Existing worktrees (including the old directory layout) were
    # resolved by their registered branch above.
    set -l branch_hash (printf '%s' "$branch" | ${pkgs.coreutils}/bin/sha256sum | string sub -l 12)
    set -l path "$root/../"(basename "$root")"-worktrees/"(string replace -a / - -- $branch)"-$branch_hash"
    if test -e "$path"
        echo "gw: worktree path already exists: $path" >&2
        return 1
    end

    if git show-ref --verify --quiet "refs/heads/$branch"
        # Local branch exists.
        git worktree add $path $branch
        or return 1
    else if git show-ref --verify --quiet "refs/remotes/origin/$branch"
        # Remote branch exists: new local branch tracking it.
        git worktree add -b $branch $path "origin/$branch"
        or return 1
    else
        # Brand-new branch off the base ref.
        if test -z "$base"
            echo "gw: no base ref (origin/HEAD unset?); pass one explicitly: gw $branch <base-ref>" >&2
            return 1
        end
        git worktree add -b $branch $path "$base"
        or return 1
    end

    cd $path
  '';
}
