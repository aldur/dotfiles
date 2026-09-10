"""Run module-generated yolo launchers on a disposable, offline host.

The wrappers mode substitutes a recording client to check launch semantics.
The cli mode drives the flake-pinned clients over a PTY, including Ctrl-G.
Neither mode reads the caller's home, credentials, configuration or PATH.
"""

import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import pyte
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time


HOME = Path('/home/tester')
WORK = HOME / 'Work'
BIN = HOME / '.local/bin'
FLAGS = {'codex': '--dangerously-bypass-approvals-and-sandbox',
         'claude': '--dangerously-skip-permissions'}


def executable(path, body, python):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f'#!{python}\n' + body)
    path.chmod(0o755)


def link(path, target):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.unlink(missing_ok=True)
    path.symlink_to(target)


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, timeout=25, **kwargs)
    assert result.returncode == 0, (command, result.returncode, result.stdout, result.stderr)
    return result


def wrappers(config):
    probe = WORK / 'probe'
    executable(probe, '''import json, os, sys
from pathlib import Path
if sys.argv[1:] == ['--version']:
    print('fixture-1')
    raise SystemExit(0)
record = {'argv': sys.argv[1:], 'env': dict(os.environ), 'cwd': os.getcwd(),
          'host_visible': Path.home().joinpath('host-only').exists()}
with Path('calls.jsonl').open('a') as stream:
    stream.write(json.dumps(record) + '\\n')
if '-p' in sys.argv:
    raise SystemExit(1 if Path('fail-refresh').exists() else 0)
print(json.dumps(record))
raise SystemExit(23 if 'exit-23' in sys.argv else 0)
''', config['python'])
    for kind in FLAGS:
        link(BIN / kind, probe)
    env = dict(os.environ, EDITOR='fixture-editor --wait', VISUAL='fixture-visual -f',
               HOST_SECRET='synthetic-host-secret')
    payload = ['resume', 'two words', '', 'line one\nline two', '$(literal)', '--no-sandbox', '--help']
    calls = WORK / 'calls.jsonl'
    stamp = HOME / '.claude/yolo-refresh'

    def invoke(launcher, args, environ=env, code=0):
        calls.unlink(missing_ok=True)
        result = subprocess.run([launcher, *args], env=environ, capture_output=True,
                                text=True, timeout=25)
        assert result.returncode == code, (args, result.returncode, result.stdout, result.stderr)
        records = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
        return result, records

    for case in config['cases']:
        for kind, launcher in case['launchers'].items():
            stamp.write_text(f'fixture-1 {int(time.time())}\n')
            for bypass in (False, True):
                result, records = invoke(launcher, (['--no-sandbox'] if bypass else []) + payload)
                assert len(records) == 1, records
                record = records[0]
                assert record['argv'] == [FLAGS[kind], *payload], record
                assert record['cwd'] == str(WORK), record
                sandboxed = case['sandbox'] and not bypass
                assert record['host_visible'] == (not sandboxed), record
                actual = record['env']
                for name in ('EDITOR', 'VISUAL'):
                    assert actual.get(name) == env[name], (name, record)
                assert ('HOST_SECRET' in actual) == (not sandboxed), record
                if kind == 'claude':
                    assert actual.get('IS_SANDBOX') == '1', record
                    assert actual.get('CLAUBBIT') == '1', record
                    assert actual.get('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC') == '1', record
                    trust = json.loads((HOME / '.claude.json').read_text())
                    assert trust['projects'][str(WORK)]['hasTrustDialogAccepted'] is True, trust
                assert ('outside the sandbox' in result.stderr) == (bypass and case['sandbox']), result.stderr
            _, records = invoke(launcher, ['--', '--help'])
            assert records[-1]['argv'] == [FLAGS[kind], '--help'], records
            _, records = invoke(launcher, ['--help'])
            assert not records, records
            invoke(launcher, ['exit-23'], code=23)
            print(f'passed: {kind}-yolo arguments, environment, exit status, sandbox={case["sandbox"]}', flush=True)

    launcher = config['cases'][3]['launchers']['claude']
    _, records = invoke(launcher, ['--online', 'resume'],
                        environ=dict(env, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'))
    assert len(records) == 1 and 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC' not in records[0]['env'], records
    _, records = invoke(launcher, ['--refresh', 'resume'])
    assert len(records) == 2, records
    assert records[0]['argv'] == ['-p', '/model', '--strict-mcp-config', '--settings', '{"disableAllHooks":true}'], records
    assert records[0]['env'].get('DISABLE_AUTOUPDATER') == '1', records
    assert 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC' not in records[0]['env'], records
    assert records[1]['argv'] == [FLAGS['claude'], 'resume'], records
    for stale in ('old-version 0\n', 'fixture-1 0\n'):
        stamp.write_text(stale)
        _, records = invoke(launcher, ['resume'])
        assert len(records) == 2 and stamp.read_text().startswith('fixture-1 '), records
    previous_stamp = stamp.read_text()
    (WORK / 'fail-refresh').touch()
    result, records = invoke(launcher, ['--refresh', 'resume'])
    assert len(records) == 2 and 'refresh failed' in result.stderr, (result.stderr, records)
    assert not stamp.with_name('yolo-refresh.next').exists()
    assert stamp.read_text() == previous_stamp, 'failed refresh replaced the cache stamp'
    print('passed: Claude online mode, model refresh, cached startup and failed-refresh fallback', flush=True)

    # The real Codex launcher must prefer either standalone layout to Nix.
    link(BIN / 'codex', config['native']['codex'])
    for relative in ('bin/codex', 'codex'):
        standalone = HOME / '.codex/packages/standalone/current' / relative
        link(standalone, probe)
        _, records = invoke(config['cases'][3]['launchers']['codex'], ['standalone'])
        assert records[-1]['argv'] == [FLAGS['codex'], 'standalone'], records
        standalone.unlink()
    print('passed: Codex standalone selection through codex-yolo', flush=True)


class Terminal:
    """Bounded PTY driver; interpret incremental redraws and retain failure output."""

    def __init__(self, command, env):
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 140, 0, 0))
        self.saved = termios.tcgetattr(slave)
        self.slave = slave
        def controlling_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        self.proc = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave,
                                     env=env, preexec_fn=controlling_terminal)
        self.screen = pyte.Screen(140, 40)
        self.stream = pyte.ByteStream(self.screen)
        self.output = b''
        self.scan = b''

    def send(self, data):
        os.write(self.master, data)

    def pump(self):
        if not select.select([self.master], [], [], 0.1)[0]:
            return
        try:
            chunk = os.read(self.master, 65536)
        except OSError as error:
            if error.errno != errno.EIO:
                raise
            return
        self.output = (self.output + chunk)[-16000:]
        self.stream.feed(chunk)
        self.scan += chunk
        # Crossterm queries cursor position; terminal feature/color probes
        # must be answered just as a real terminal would answer them.
        for query, reply in ((b'\x1b[6n', b'\x1b[1;1R'),
                             (b'\x1b[c', b'\x1b[?1;2c'),
                             (b'\x1b]10;?\x1b\\', b'\x1b]10;rgb:ffff/ffff/ffff\x1b\\'),
                             (b'\x1b]11;?\x1b\\', b'\x1b]11;rgb:0000/0000/0000\x1b\\')):
            while query in self.scan:
                self.send(reply)
                self.scan = self.scan.replace(query, b'', 1)
        self.scan = self.scan[-64:]

    def text(self):
        return '\n'.join(self.screen.display)

    def until(self, condition, description, timeout=35):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.pump()
            if condition():
                return
            if self.proc.poll() is not None:
                break
        raise AssertionError(f'{description}\nexit={self.proc.poll()}\n{self.text()[-16000:]}\nraw={self.output[-500:]!r}')

    def close(self):
        if self.proc.poll() is None:
            os.killpg(self.proc.pid, signal.SIGTERM)
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(self.proc.pid, signal.SIGKILL)
                self.proc.wait(timeout=3)
        os.close(self.master)
        os.close(self.slave)


def cli(config):
    for kind, binary in config['native'].items():
        link(BIN / kind, binary)
    editor = BIN / 'fixture-editor'
    executable(editor, '''import json, os, sys
from pathlib import Path
prompt = Path(sys.argv[-1])
record = {'argv': sys.argv[1:], 'before': prompt.read_text(),
          'tty': [os.isatty(fd) for fd in (0, 1, 2)], 'cwd': os.getcwd()}
prompt.write_text('edited-in-external-editor')
result = Path('editor-result.json')
result.with_suffix('.tmp').write_text(json.dumps(record))
result.with_suffix('.tmp').replace(result)
''', config['python'])
    launchers = config['cases'][3]['launchers']
    version = run([str(BIN / 'claude'), '--version']).stdout.split()[0]
    (HOME / '.claude/yolo-refresh').write_text(f'{version} {int(time.time())}\n')
    for kind, launcher in launchers.items():
        version = run([launcher, '--version']).stdout.strip()
        print(f'testing real {kind}-yolo: {version}', flush=True)
        for variable in ('EDITOR', 'VISUAL'):
            result = WORK / 'editor-result.json'
            result.unlink(missing_ok=True)
            env = dict(os.environ)
            env.pop('VISUAL', None)
            env['EDITOR'] = f'{editor} --editor'
            if variable == 'VISUAL':
                env['VISUAL'] = f'{editor} --visual'
            args = ['--no-alt-screen'] if kind == 'codex' else []
            terminal = Terminal([launcher, *args], env)
            try:
                ready = 'model:gpt-5' if kind == 'codex' else 'bypasspermissions'
                def screen():
                    return re.sub(r'\s+', '', terminal.text()).lower()
                terminal.until(lambda: ready in screen() or 'doyouwanttousethisapikey?' in screen(),
                               f'{kind} composer did not become ready')
                if ready not in screen():
                    # Approve only the synthetic API key in the disposable home.
                    terminal.send(b'\x1b[A\r')
                    terminal.until(lambda: ready in screen(), f'{kind} composer did not become ready after fixture-key approval')
                terminal.send(b'original-editor-draft')
                terminal.until(lambda: 'original-editor-draft' in terminal.text(), f'{kind} did not accept input')
                terminal.send(b'\x07')
                terminal.until(result.exists, f'{kind} {variable}: Ctrl-G did not launch editor')
                record = json.loads(result.read_text())
                assert 'original-editor-draft' in record['before'], record
                assert record['argv'][0] == f'--{variable.lower()}', record
                assert all(record['tty']), record
                assert record['cwd'] == str(WORK), record
                terminal.until(lambda: 'edited-in-external-editor' in terminal.text(), f'{kind} did not restore edited draft')
                terminal.send(b'\x15')
                # Send distinct key events: TUIs can treat a combined control
                # sequence and text write as pasted input.
                terminal.until(lambda: 'edited-in-external-editor' not in terminal.text(),
                               f'{kind} did not clear the edited draft')
                terminal.send(b'/exit')
                terminal.until(lambda: '/exit' in terminal.text(), f'{kind} did not accept the exit command')
                terminal.send(b'\r')
                terminal.until(lambda: terminal.proc.poll() is not None, f'{kind} did not exit', timeout=10)
                assert terminal.proc.returncode == 0, terminal.text()
                assert termios.tcgetattr(terminal.slave) == terminal.saved, f'{kind} left terminal settings changed'
                print(f'passed: real {kind}-yolo {variable} editor round trip and terminal cleanup', flush=True)
            finally:
                terminal.close()


def main():
    manifest, mode, *inside = sys.argv[1:]
    config = json.loads(Path(manifest).read_text())
    if inside:
        (wrappers if mode == 'wrappers' else cli)(config)
        return
    with tempfile.TemporaryDirectory(prefix='agent-yolo-e2e-') as directory:
        fixture = Path(directory)
        home = fixture / 'home'
        for name in ('Work', '.local/bin', '.claude', '.codex'):
            (home / name).mkdir(parents=True, exist_ok=True)
        (home / 'host-only').write_text('synthetic private host file')
        (home / '.codex/config.toml').write_text(
            'model = "gpt-5"\ncheck_for_update_on_startup = false\n'
            '[projects."/home/tester/Work"]\ntrust_level = "trusted"\n')
        (home / '.codex/auth.json').write_text('{"OPENAI_API_KEY":"sk-fixture-no-network"}')
        (home / '.claude/settings.json').write_text(json.dumps({
            'theme': 'dark', 'skipDangerousModePermissionPrompt': True,
            'env': {'ANTHROPIC_API_KEY': 'sk-ant-fixture-no-network'},
        }))
        (home / '.claude.json').write_text(json.dumps({
            'hasCompletedOnboarding': True, 'theme': 'dark',
            'customApiKeyResponses': {'approved': ['sk-ant-fixture-no-network'], 'rejected': []},
        }))
        passwd = fixture / 'passwd'
        passwd.write_text(f'tester:x:{os.getuid()}:{os.getgid()}::/home/tester:{config["bash"]}\n')
        runtime = f'/run/user/{os.getuid()}'
        command = [config['bwrap'], '--unshare-pid', '--unshare-net', '--die-with-parent',
                   '--tmpfs', '/', '--ro-bind', '/nix/store', '/nix/store',
                   '--dev', '/dev', '--proc', '/proc', '--tmpfs', '/tmp',
                   '--bind', str(home), str(HOME), '--ro-bind', str(passwd), '/etc/passwd',
                   '--ro-bind', config['certificates'], '/etc/static/ssl/certs',
                   '--symlink', '/etc/static/ssl/certs/ca-bundle.crt', '/etc/ssl/certs/ca-certificates.crt',
                   '--symlink', config['bash'], '/bin/bash', '--symlink', config['bash'], '/bin/sh',
                   '--ro-bind', str(Path(__file__).resolve()), '/test.py',
                   '--dir', runtime, '--chdir', str(WORK), '--clearenv',
                   '--setenv', 'HOME', str(HOME), '--setenv', 'USER', 'tester',
                   '--setenv', 'XDG_RUNTIME_DIR', runtime, '--setenv', 'TERM', 'xterm-256color',
                   '--setenv', 'PATH', f'{BIN}:{config["path"]}',
                   '--setenv', 'LANG', 'C.UTF-8',
                   '--', config['dbus'], f'--config-file={config["dbusConfig"]}', '--',
                   config['python'], '/test.py', manifest, mode, 'inside']
        subprocess.run(command, check=True, timeout=240)


if __name__ == '__main__':
    main()
