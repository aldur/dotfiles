"""Real direnv approvals, using only the synthetic host's files and home."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


wrapper = sys.argv[1]
direnv = "@direnv@"
git = "@git@"
home = Path.home()
config = home / ".config/direnv"
config.mkdir(parents=True, exist_ok=True)
(config / "direnvrc").write_text(Path("@stdlib@").read_text())
(config / "direnv.toml").write_text("[global]\nstrict_env = true\ndisable_stdin = true\n")
env = {key: value for key, value in os.environ.items() if not key.startswith("DIRENV_")}
env.update(DIRENV_CONFIG=str(config), XDG_DATA_HOME=str(home / ".local/share"))
env["PATH"] = str(Path(direnv).parent) + ":" + env["PATH"]
data = Path(env["XDG_DATA_HOME"]) / "direnv"


def run(args, *, cwd, environ=env, check=True):
    result = subprocess.run(args, cwd=cwd, env=environ, capture_output=True, text=True, timeout=20)
    if check and result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result


def load(project):
    result = run([direnv, "export", "json"], cwd=project, check=False)
    for key, value in json.loads(result.stdout or "{}").items():
        if value is None:
            env.pop(key, None)
        else:
            env[key] = value
    return result


def allow(project):
    run([direnv, "allow"], cwd=project)
    load(project)


def snapshot():
    return {str(path): path.read_bytes() for path in data.rglob("*") if path.is_file()}


with tempfile.TemporaryDirectory(prefix="direnv-project-", dir=home) as temporary:
    project = Path(temporary)
    (project / "nix").mkdir()
    (project / "scripts").mkdir()
    inputs = ["flake.nix", "flake.lock", "nix/devshell.nix", "nix/flake.lock",
              "scripts/activate.sh", ".envrc.extra", "scripts/with space.sh"]
    ordinary = ["app.py", "environment data.json", "scripts/without-extension", "image.png"]
    for name in inputs + ordinary:
        (project / name).write_text("# original\n")
    (project / "scripts/activate.sh").write_text("export PROJECT_VALUE=approved\n")
    (project / ".envrc").write_text(
        "source scripts/activate.sh\n"
        "export PROJECT_CACHE=$(direnv_layout_dir)\n"
        "mkdir -p \"$PROJECT_CACHE\"\n"
        "printf host-cache > \"$PROJECT_CACHE/marker\"\n"
    )
    run([git, "init", "--quiet"], cwd=project)
    with tempfile.TemporaryDirectory(prefix="direnv-submodule-", dir=home) as origin:
        run([git, "init", "--quiet"], cwd=origin)
        (Path(origin) / "imported.nix").write_text("# submodule input\n")
        run([git, "add", "."], cwd=origin)
        run([git, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
             "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "fixture"], cwd=origin)
        run([git, "-c", "protocol.file.allow=always", "submodule", "add", "--quiet", origin, "vendor"], cwd=project)
    inputs.append("vendor/imported.nix")
    run([git, "add", "."], cwd=project)
    nested = project / "entered/nested"
    nested.mkdir(parents=True)
    load(nested)
    assert "PROJECT_VALUE" not in env
    allow(nested)  # Approves .envrc; global config discovers tracked inputs.
    assert "PROJECT_VALUE" not in env and env.get("DIRENV_REQUIRED")
    allow(nested)
    assert env["PROJECT_VALUE"] == "approved"
    cache = Path(env["PROJECT_CACHE"])
    assert cache.is_relative_to(data / "layouts")
    assert not (project / ".direnv").exists()

    # Ordinary source/data changes do not trigger a reload or approval prompt.
    for name in ordinary:
        path = project / name
        path.write_text("changed ordinary source\n")
        os.utime(path, (time.time() + 1,) * 2)
        result = load(project)
        assert not result.returncode and not result.stdout, name
        assert env["PROJECT_VALUE"] == "approved" and not env.get("DIRENV_REQUIRED"), name

    # Selected inputs block loading without declarations in .envrc.
    # direnv's watch list uses seconds, so advance mtime without sleeping.
    for index, name in enumerate(inputs):
        path = project / name
        path.write_text(path.read_text() + "# changed\n")
        modified = time.time() + index + 2
        os.utime(path, (modified, modified))
        load(project)
        assert "PROJECT_VALUE" not in env, name
        assert name in env.get("DIRENV_REQUIRED", ""), name
        assert (cache / "marker").read_text() == "host-cache"
        allow(project)
        assert env["PROJECT_VALUE"] == "approved", name

    (project / "nix/devshell.nix").unlink()
    load(project)
    assert "PROJECT_VALUE" not in env
    assert run([direnv, "allow"], cwd=project, check=False).returncode != 0
    (project / "nix/devshell.nix").write_text("# restored with new contents\n")
    allow(project)
    assert env["PROJECT_VALUE"] == "approved"

    # Staging a new dependency changes the watched index and requires approval.
    (project / "nix/new-input.nix").write_text("new tracked input\n")
    run([git, "add", "nix/new-input.nix"], cwd=project)
    index = project / ".git/index"
    os.utime(index, (time.time() + 30,) * 2)
    load(project)
    assert "PROJECT_VALUE" not in env and "nix/new-input.nix" in env.get("DIRENV_REQUIRED", "")
    allow(project)
    assert env["PROJECT_VALUE"] == "approved"

    # Git failures must stop activation, even when .envrc is already allowed.
    original_index = index.read_bytes()
    index.write_bytes(b"invalid fixture index")
    os.utime(index, (time.time() + 31,) * 2)
    result = load(project)
    assert result.returncode and "PROJECT_VALUE" not in env
    index.write_bytes(original_index)
    os.utime(index, (time.time() + 32,) * 2)
    # A failed evaluation drops its watches; request a reload after repair.
    run([direnv, "reload"], cwd=project)
    os.utime(project / ".envrc", (time.time() + 45,) * 2)
    load(project)
    assert env["PROJECT_VALUE"] == "approved"

    # An agent can approve its private environment without approving the host's.
    (project / "scripts/activate.sh").write_text("export PROJECT_VALUE=edited\n")
    os.utime(project / "scripts/activate.sh", (time.time() + 20,) * 2)
    load(project)
    assert "PROJECT_VALUE" not in env
    original = snapshot()
    script = '''
set -eu
eval "$(direnv export bash)"
direnv allow
eval "$(direnv export bash)"
direnv allow
eval "$(direnv export bash)"
test "$PROJECT_VALUE" = edited
printf sandbox-cache > "$PROJECT_CACHE/marker"
'''
    run([wrapper, "--workspace", str(project), "--", "@bash@", "-c", script], cwd=project)
    assert snapshot() == original
    load(project)
    assert "PROJECT_VALUE" not in env and env.get("DIRENV_REQUIRED")
    allow(project)
    assert env["PROJECT_VALUE"] == "edited"

    # Direct, parent and symlink grants cannot expose host approvals as writable.
    alias = project / "host-direnv"
    alias.symlink_to(data, target_is_directory=True)
    for grant in (data, data.parent, alias):
        result = run([wrapper, "--workspace", str(project), "--rw", str(grant), "--", "true"], cwd=project, check=False)
        assert result.returncode and "host direnv" in result.stderr
    alias.unlink()

    # A custom host XDG_DATA_HOME receives the same protection, even before
    # direnv has created its state directory there.
    with tempfile.TemporaryDirectory(prefix="custom-data-", dir=home) as custom:
        custom_env = dict(env, XDG_DATA_HOME=custom)
        for grant in (custom, data):
            result = run([wrapper, "--workspace", str(project), "--rw", str(grant), "--", "true"],
                         cwd=project, environ=custom_env, check=False)
            assert result.returncode and "host direnv" in result.stderr
        custom_data = Path(custom) / "direnv"
        custom_data.mkdir()
        result = run([wrapper, "--workspace", str(project), "--rw", str(custom_data), "--", "true"],
                     cwd=project, environ=custom_env, check=False)
        assert result.returncode and "host direnv" in result.stderr

    if Path("/persist/home/tester/.local/share/direnv").exists():
        for grant in ("/persist/home/tester/.local/share/direnv", "/persist/home/tester/.local/share"):
            result = run([wrapper, "--workspace", str(project), "--rw", grant, "--", "true"], cwd=project, check=False)
            assert result.returncode and "host direnv" in result.stderr

    # Existing hard links to approval records also remain read-only.
    original = snapshot()
    approval = next((data / "allow").iterdir())
    os.link(approval, project / "approval-alias")
    run([wrapper, "--workspace", str(project), "--", "@bash@", "-c",
         "if echo changed > approval-alias; then exit 1; fi"], cwd=project)
    assert snapshot() == original
    (project / "approval-alias").unlink()

    run([direnv, "deny"], cwd=project)
    load(project)
    assert "PROJECT_VALUE" not in env
    print("passed: focused direnv reapproval, ordinary edits skip reload, subdirectories, Git errors and private host state", flush=True)

# A package .envrc must approve parent and sibling inputs under its own identity,
# even when the repository root has no .envrc. No Nix evaluation is needed.
with tempfile.TemporaryDirectory(prefix="direnv-parent-", dir=home) as temporary:
    project = Path(temporary)
    package = project / "packages/child"
    entered = package / "deeper"
    entered.mkdir(parents=True)
    inputs = ["flake.nix", "flake.lock", "nix/shared.nix",
              "packages/sibling/activate.sh", "packages/child/local.nix"]
    for name in inputs + ["packages/sibling/app.py"]:
        path = project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("# original\n")
    (package / ".envrc").write_text(
        "echo activated >> activation-log\nexport SUBDIR_ENV=loaded\n"
    )
    marker = package / "activation-log"
    run([git, "init", "--quiet"], cwd=project)
    run([git, "add", "."], cwd=project)
    load(entered)
    allow(entered)
    assert "SUBDIR_ENV" not in env and "../../flake.nix" in env.get("DIRENV_REQUIRED", "")
    assert not marker.exists()
    allow(entered)
    assert env["SUBDIR_ENV"] == "loaded" and marker.read_text() == "activated\n"

    for index, name in enumerate(inputs):
        path = project / name
        path.write_text("# changed\n")
        os.utime(path, (time.time() + index + 1,) * 2)
        before = marker.read_text()
        load(entered)
        assert "SUBDIR_ENV" not in env and marker.read_text() == before, name
        assert os.path.relpath(path, package) in env.get("DIRENV_REQUIRED", "").split(":"), name
        allow(entered)
        assert env["SUBDIR_ENV"] == "loaded", name

    # Widening the Git pathspec must not start watching ordinary sibling files.
    ordinary = project / "packages/sibling/app.py"
    ordinary.write_text("changed source\n")
    os.utime(ordinary, (time.time() + 10,) * 2)
    before = marker.read_text()
    result = load(entered)
    assert not result.returncode and not result.stdout and marker.read_text() == before

    # The parent index is watched too, so staged new inputs join the check.
    (project / "nix/new.nix").write_text("# new parent input\n")
    run([git, "add", "nix/new.nix"], cwd=project)
    os.utime(project / ".git/index", (time.time() + 20,) * 2)
    load(entered)
    assert "SUBDIR_ENV" not in env and "../../nix/new.nix" in env.get("DIRENV_REQUIRED", "")
    assert marker.read_text() == before
    allow(entered)
    assert env["SUBDIR_ENV"] == "loaded"

    run([direnv, "deny"], cwd=entered)
    load(entered)
    before = marker.read_text()
    assert "SUBDIR_ENV" not in env
    allow(entered)  # Denial must also revoke the package's parent-file approvals.
    assert "SUBDIR_ENV" not in env and marker.read_text() == before
    assert "../../flake.nix" in env.get("DIRENV_REQUIRED", "")
    allow(entered)
    assert env["SUBDIR_ENV"] == "loaded" and not (project / ".envrc").exists()
    run([direnv, "deny"], cwd=entered)
    load(entered)
    print("passed: package envrc approves parent/sibling inputs before execution, skips ordinary edits and revokes approvals", flush=True)

# Non-Git environments retain native approval and explicit input declarations.
with tempfile.TemporaryDirectory(prefix="plain-direnv-", dir=home) as temporary:
    project = Path(temporary)
    (project / ".envrc").write_text("export SIMPLE_ENV=loaded\n")
    allow(project)
    assert env["SIMPLE_ENV"] == "loaded"
    (project / "extra-input").write_text("extra\n")
    (project / ".envrc").write_text("require_allowed extra-input\nexport SIMPLE_ENV=loaded\n")
    os.utime(project / ".envrc", (time.time() + 40,) * 2)
    load(project)
    assert "SIMPLE_ENV" not in env
    allow(project)
    assert "SIMPLE_ENV" not in env and env.get("DIRENV_REQUIRED") == "extra-input"
    allow(project)
    assert env["SIMPLE_ENV"] == "loaded"
    run([direnv, "deny"], cwd=project)
    load(project)

# An unavailable approval checker must not be treated as a successful check.
result = run(["@bash@", "-c", '''
eval "$("$1" stdlib)"
failed_checker() { if [[ $1 == check-required ]]; then return 42; fi; }
direnv=failed_checker
require_allowed unused-fixture
echo should-not-run
''', "test-checker-failure", direnv], cwd=home, check=False)
assert result.returncode and "should-not-run" not in result.stdout
print("passed: ordinary direnv environments, explicit extra inputs and checker failures", flush=True)
