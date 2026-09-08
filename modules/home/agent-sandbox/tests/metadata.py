"""Synthetic repository/configuration fixtures; never use real credentials."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


wrapper = sys.argv[1]
git = "@git@"
DENIED = '''
import errno
from pathlib import Path
def denied(operation):
    try:
        operation()
    except OSError as error:
        assert error.errno in (errno.EROFS, errno.EBUSY, errno.EACCES, errno.EPERM), error
    else:
        raise AssertionError('protected operation succeeded')
'''


def call(args, **kwargs):
    return subprocess.run(args, check=True, timeout=20, capture_output=True, text=True, **kwargs)


def sandbox(workspace, code, *options, check=True):
    result = subprocess.run(
        [wrapper, "--workspace", str(workspace), *options, "--", sys.executable, "-c", DENIED + code],
        capture_output=True, text=True, timeout=20,
    )
    if check and result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result


def repository(path):
    call([git, "init", "--quiet", str(path)])
    call([git, "-C", str(path), "config", "user.name", "Fixture"])
    call([git, "-C", str(path), "config", "user.email", "fixture@example.invalid"])
    (path / "file").write_text("original\n")
    call([git, "-C", str(path), "add", "file"])
    call([git, "-C", str(path), "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "fixture"])


with tempfile.TemporaryDirectory(prefix="metadata-", dir="/home/tester") as temporary:
    base = Path(temporary)
    repo = base / "repo"
    repository(repo)
    for name in (".agents", ".codex", ".claude"):
        (repo / name).mkdir()
        (repo / name / "fixture").write_text("original")
    (repo / "AGENTS.md").write_text("fixture instructions")
    sandbox(repo, '''
import subprocess
for name in ('.git',):
    denied(lambda: (Path(name) / 'marker').write_text('changed'))
    denied(lambda: Path(name).rename(name + '-moved'))
denied(lambda: Path('.lazygit.yml').write_text('changed'))
denied(lambda: Path('.lazygit.yml').unlink())
for name in ('.agents', '.codex', '.claude'):
    (Path(name) / 'fixture').write_text('project configuration')
Path('.mcp.json').write_text('{}')
Path('.mcp.json').unlink()
# Project instructions follow the normal workspace write grant, including
# creating missing files and the atomic replacement used by editors.
assert not Path('CLAUDE.md').exists()
assert not Path('CLAUDE.local.md').exists()
Path('AGENTS.md').write_text('edited instructions')
Path('instructions.tmp').write_text('replaced instructions')
Path('instructions.tmp').replace('AGENTS.md')
Path('CLAUDE.md').write_text('new instructions')
Path('CLAUDE.local.md').write_text('temporary instructions')
Path('CLAUDE.local.md').unlink()
Path('file').write_text('edited\\n')
for args in (['status', '--short'], ['diff'], ['log', '-1', '--oneline']):
    subprocess.run([GIT, *args], check=True, capture_output=True)
assert subprocess.run([GIT, 'add', 'file'], capture_output=True).returncode != 0
'''.replace("GIT", repr(git)))
    assert (repo / "file").read_text() == "edited\n"
    assert (repo / "AGENTS.md").read_text() == "replaced instructions"
    assert (repo / "CLAUDE.md").read_text() == "new instructions"
    assert not (repo / "CLAUDE.local.md").exists()
    assert not (repo / ".mcp.json").exists()
    sandbox(repo, "denied(lambda: Path('AGENTS.md').write_text('changed'))", "--ro", str(repo / "AGENTS.md"))

    # Instructions can also use ordinary links within the granted workspace.
    instructions = repo / "docs"
    instructions.mkdir()
    (instructions / "guide.md").write_text("original instructions")
    (instructions / "AGENTS.md").symlink_to("guide.md")
    os.link(instructions / "guide.md", instructions / "CLAUDE.md")
    sandbox(repo, "Path('docs/AGENTS.md').write_text('symlink edit'); Path('docs/CLAUDE.md').write_text('hardlink edit')")
    assert (instructions / "guide.md").read_text() == "hardlink edit"
    result = sandbox(repo, '''
import subprocess
subprocess.run([GIT, 'add', 'file'], check=True)
subprocess.run([GIT, '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'sandbox edit'], check=True)
Path('.codex/fixture').write_text('project configuration')
'''.replace("GIT", repr(git)), "--git-write")
    assert "WARNING: --git-write" in result.stderr

    # Additional grants and resolved aliases cannot override these restrictions.
    sandbox(repo, "denied(lambda: Path('.git/config').write_text('changed'))", "--rw", str(repo / ".git"))
    os.link(repo / '.git/config', repo / 'git-config-alias')
    sandbox(repo, "denied(lambda: Path('git-config-alias').write_text('changed'))")
    (repo / 'git-config-alias').unlink()
    alias = base / "git-alias"
    alias.symlink_to(repo / ".git")
    sandbox(repo, f"denied(lambda: Path({str(alias / 'config')!r}).write_text('changed'))", "--rw", str(alias))
    sandbox(repo, "denied(lambda: Path('.git/config').write_text('changed'))", "--git-write", "--ro", str(repo / ".git"))

    # Worktrees need both the gitdir target and its common directory to read Git.
    worktree = base / "worktree"
    call([git, "-C", str(repo), "worktree", "add", "--quiet", "--detach", str(worktree)])
    gitdir = Path((worktree / ".git").read_text().strip().removeprefix("gitdir: "))
    sandbox(worktree, f'''
import subprocess
subprocess.run([{git!r}, 'status', '--short'], check=True)
subprocess.run([{git!r}, 'log', '-1', '--oneline'], check=True)
denied(lambda: Path('.git').write_text('changed'))
denied(lambda: Path({str(gitdir / 'HEAD')!r}).write_text('changed'))
denied(lambda: Path({str(repo / '.git/config')!r}).write_text('changed'))
''', "--rw", str(repo / ".git/hooks"))
    sandbox(worktree, f"import subprocess; Path('file').write_text('worktree edit'); subprocess.run([{git!r}, 'add', 'file'], check=True)", "--git-write")

    # Nested repositories and submodules, plus launching below a repository root.
    nested = repo / "nested"
    repository(nested)
    sandbox(repo, "denied(lambda: Path('nested/.git/config').write_text('changed'))")
    call([git, "-C", str(repo), "-c", "protocol.file.allow=always", "submodule", "add", "--quiet", str(nested), "module"])
    sandbox(repo / "module", f"import subprocess; subprocess.run([{git!r}, 'status', '--short'], check=True); denied(lambda: Path('.git').unlink())")
    subdir = repo / "src"
    subdir.mkdir()
    sandbox(subdir, f"import subprocess; subprocess.run([{git!r}, 'log', '-1'], check=True); denied(lambda: Path({str(repo / '.git/config')!r}).write_text('changed')); assert not Path({str(repo / 'file')!r}).exists()")
    sandbox(subdir, f"assert Path({str(repo / 'AGENTS.md')!r}).read_text() == 'replaced instructions'; denied(lambda: Path({str(repo / 'AGENTS.md')!r}).write_text('changed'))")
    sandbox(subdir, f"Path({str(repo / 'AGENTS.md')!r}).write_text('explicit grant edit')", "--rw", str(repo / "AGENTS.md"))
    assert (repo / "AGENTS.md").read_text() == "explicit grant edit"

    # Symlinked metadata fails closed instead of protecting only its target.
    empty = base / "empty"
    empty.mkdir()
    (empty / ".git").symlink_to(repo / ".git")
    result = sandbox(empty, "raise AssertionError('must not run')", check=False)
    assert result.returncode != 0 and "crosses a symlink" in result.stderr
    (empty / ".git").unlink()
    (base / "reference-lazygit.yml").write_text("{}")
    os.link(base / "reference-lazygit.yml", empty / ".lazygit.yml")
    result = sandbox(empty, "raise AssertionError('must not run')", check=False)
    assert result.returncode != 0 and "hard links" in result.stderr
    (empty / ".lazygit.yml").unlink()

    # Missing paths are reserved only while an owner is alive. Parallel launches
    # do not remove each other's placeholders or share private config files.
    hold = '''
import time
from pathlib import Path
print('ready', flush=True)
while not Path('release').exists():
    time.sleep(0.02)
'''
    first = subprocess.Popen([wrapper, "--workspace", str(empty), "--", sys.executable, "-c", hold], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        assert first.stdout.readline().strip() == "ready"
        sandbox(empty, "denied(lambda: Path('.lazygit.yml').write_text('changed'))")
        assert (empty / ".lazygit.yml").exists()
        (empty / "release").touch()
        stdout, stderr = first.communicate(timeout=5)
        assert first.returncode == 0, stdout + stderr
    finally:
        if first.poll() is None:
            first.kill()
            first.wait()
    assert sorted(path.name for path in empty.iterdir()) == ["release"]
    (empty / "release").unlink()
    first = subprocess.Popen([wrapper, "--workspace", str(empty), "--", sys.executable, "-c", hold], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        assert first.stdout.readline().strip() == "ready"
        first.terminate()
        first.communicate(timeout=5)
    finally:
        if first.poll() is None:
            first.kill()
            first.wait()
    # Also reaps reservations if the shell was terminated before its child.
    sandbox(empty, "pass")
    assert not list(empty.iterdir())
    print("passed: repository metadata, aliases, worktrees, submodules, opt-in Git writes and reservation lifecycle", flush=True)

    # Application homes are the host homes, shared by every project. The
    # agent installation stays read-only, and an explicit grant cannot spell
    # the state another way.
    other = base / "other"
    repository(other)
    for kind in ("codex", "claude"):
        host = Path.home() / f".{kind}"
        auth_name = "auth.json" if kind == "codex" else ".credentials.json"
        sandbox(repo, f'''
import sqlite3
root = Path.home() / '.{kind}'
(root / 'sessions').mkdir(exist_ok=True)
(root / 'sessions/thread').write_text('A session')
temporary = root / 'replacement'
temporary.write_text('{{"token":"refresh"}}')
temporary.replace(root / {auth_name!r})
with sqlite3.connect(root / 'fixture.sqlite') as db:
    db.execute('CREATE TABLE IF NOT EXISTS fixture(value TEXT)')
    db.execute("INSERT INTO fixture VALUES ('A')")
denied(lambda: (root / 'bin/tool').write_text('changed'))
''', '--profile', kind)
        assert (host / 'sessions/thread').read_text() == 'A session'
        assert (host / auth_name).read_text() == '{"token":"refresh"}'
        sandbox(other, f'''
import sqlite3
root = Path.home() / '.{kind}'
assert (root / 'sessions/thread').read_text() == 'A session'
with sqlite3.connect(root / 'fixture.sqlite') as db:
    assert db.execute('SELECT value FROM fixture').fetchone()[0] == 'A'
''', '--profile', kind)
        (host / 'fixture.sqlite').unlink()
        result = sandbox(repo, 'pass', '--profile', kind, '--rw', str(host), check=False)
        assert result.returncode != 0 and 'must use --profile' in result.stderr

    # ~/.claude.json is a file mount. A rename over it fails with EBUSY, so a
    # writer must fall back to an in-place write, as Claude Code does. A
    # missing file is created before the first launch, so a first run inside
    # the sandbox reaches the host too.
    config = Path.home() / '.claude.json'
    original = config.read_bytes()
    sandbox(repo, '''
import errno, json
config = Path.home() / '.claude.json'
assert json.loads(config.read_text())['fixture']
temporary = Path.home() / '.claude.json.tmp'
temporary.write_text('{"fixture":"sandbox"}')
try:
    temporary.replace(config)
except OSError as error:
    assert error.errno == errno.EBUSY, error
    config.write_text(temporary.read_text())
else:
    raise AssertionError('configuration must be a shared mount point')
''', '--profile', 'claude')
    assert json.loads(config.read_text())['fixture'] == 'sandbox'
    config.unlink()
    sandbox(repo, "assert (Path.home() / '.claude.json').read_text() == '{}\\n'", '--profile', 'claude')
    assert config.stat().st_mode & 0o777 == 0o600
    config.write_bytes(original)

    if Path('/persist/home/tester/.codex').exists():
        result = sandbox(repo, 'pass', '--profile', 'codex', '--rw', '/persist/home/tester/.codex', check=False)
        assert result.returncode != 0 and 'must use --profile' in result.stderr
        preserved = Path('/home/tester/Work/preserved-repo')
        repository(preserved)
        sandbox(preserved, "denied(lambda: Path('/persist/home/tester/Work/preserved-repo/.git/config').write_text('changed'))", '--rw', '/persist/home/tester/Work/preserved-repo/.git/config')

        processes = []
        try:
            for index, workspace in enumerate((str(preserved), '/persist/home/tester/Work/preserved-repo')):
                program = f"import time; from pathlib import Path; print('ready', flush=True)\nwhile not Path('release-{index}').exists(): time.sleep(0.02)"
                process = subprocess.Popen([wrapper, '--workspace', workspace, '--', sys.executable, '-c', program], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                processes.append(process)
                assert process.stdout.readline().strip() == 'ready'
            (preserved / 'release-0').touch()
            processes[0].communicate(timeout=5)
            assert processes[0].returncode == 0
            assert (preserved / '.lazygit.yml').exists(), 'reservation lost through a bind alias'
            (preserved / 'release-1').touch()
            processes[1].communicate(timeout=5)
            assert processes[1].returncode == 0
            assert not (preserved / '.lazygit.yml').exists()
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()

    # Concurrent tasks in the same project deliberately share state.
    program = '''
from pathlib import Path
import time
(Path.home() / '.codex/memory').write_text('concurrent update')
print('ready', flush=True)
while not Path('release').exists():
    time.sleep(0.02)
'''
    first = subprocess.Popen([wrapper, '--workspace', str(empty), '--profile', 'codex', '--', sys.executable, '-c', program], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        assert first.stdout.readline().strip() == 'ready'
        sandbox(empty, "assert (Path.home() / '.codex/memory').read_text() == 'concurrent update'", '--profile', 'codex')
        (empty / '.lazygit.yml').write_text('human edit')
        (empty / 'release').touch()
        stdout, stderr = first.communicate(timeout=5)
        assert first.returncode == 0, stdout + stderr
        assert (empty / '.lazygit.yml').read_text() == 'human edit'
    finally:
        if first.poll() is None:
            first.kill()
            first.wait()
    assert not list(Path('/tmp').glob('agent-sandbox-private-*'))
    print('passed: shared state, atomic rewrites, SQLite and concurrency', flush=True)
