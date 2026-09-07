"""Optional offline smoke test using the locally installed native agents.

Usage: python3 cli-smoke.py /path/to/agent-sandbox /path/to/bwrap
Requires dbus-run-session on PATH. All configuration and credentials are dummy
fixtures in a disposable outer namespace with networking disabled.
"""

import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile


if len(sys.argv) == 2 and sys.argv[1] == 'inside':
    wrapper = os.environ['SMOKE_WRAPPER']
    for kind, args in [('codex', ['--version']), ('codex', ['resume', '--help']), ('codex', ['login', 'status']), ('claude', ['--version']), ('claude', ['--help']), ('claude', ['auth', 'status'])]:
        result = subprocess.run([wrapper, '--profile', kind, '--ro', f'/opt/{kind}', '--', f'/opt/{kind}', *args], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0 or (kind == 'claude' and args == ['auth', 'status'] and result.returncode == 1), result.stderr
        if args == ['--version']:
            print(result.stdout.strip(), flush=True)
        print('passed CLI smoke:', kind, *args, flush=True)
    proc = subprocess.Popen([wrapper, '--profile', 'codex', '--ro', '/opt/codex', '--', '/opt/codex', 'app-server'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    def send(message):
        proc.stdin.write(json.dumps(message) + '\n')
        proc.stdin.flush()
    def response(identifier):
        while True:
            assert select.select([proc.stdout], [], [], 20)[0], 'app-server response timeout'
            line = proc.stdout.readline()
            assert line, proc.stderr.read()
            message = json.loads(line)
            if message.get('id') == identifier:
                assert 'error' not in message, message
                return message['result']
    try:
        send({'id': 1, 'method': 'initialize', 'params': {'clientInfo': {'name': 'sandbox-smoke', 'version': '1'}, 'capabilities': {'experimentalApi': True}}})
        response(1)
        send({'method': 'initialized', 'params': {}})
        send({'id': 2, 'method': 'config/read', 'params': {'includeLayers': False}})
        config = response(2)
        assert config['config']['model'] == 'gpt-5', config
        send({'id': 3, 'method': 'thread/list', 'params': {'limit': 1}})
        response(3)
        print('passed CLI smoke: Codex app-server initialization, configuration and session listing', flush=True)
    finally:
        proc.stdin.close()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.terminate()
            proc.wait(timeout=5)
    raise SystemExit(0)

wrapper, bwrap = sys.argv[1:]
with tempfile.TemporaryDirectory(prefix='agent-cli-smoke-') as directory:
    fixture = Path(directory)
    home = fixture / 'home'
    for name in ('Work', '.codex', '.claude'):
        (home / name).mkdir(parents=True)
    (home / '.codex/config.toml').write_text('model = "gpt-5"\ncheck_for_update_on_startup = false\n')
    (home / '.codex/auth.json').write_text('{"OPENAI_API_KEY":"sk-fixture-no-network"}')
    (home / '.claude/settings.json').write_text('{}')
    (home / '.claude.json').write_text('{"hasCompletedOnboarding":true}')
    passwd = fixture / 'passwd'
    passwd.write_text(f'tester:x:{os.getuid()}:{os.getgid()}::/home/tester:/bin/bash\n')
    dbus = Path(shutil.which('dbus-run-session')).resolve()
    dbus_config = dbus.parent.parent / 'share/dbus-1/session.conf'
    command = [bwrap, '--unshare-pid', '--unshare-net', '--tmpfs', '/', '--ro-bind', '/nix/store', '/nix/store', '--dev', '/dev', '--proc', '/proc', '--tmpfs', '/tmp', '--bind', str(home), '/home/tester', '--ro-bind', str(passwd), '/etc/passwd']
    for name in ('/run/current-system/sw', '/lib', '/lib64'):
        if Path(name).exists():
            command += ['--ro-bind', name, name]
    for name in ('codex', 'claude'):
        command += ['--ro-bind', str((Path.home() / '.local/bin' / name).resolve()), f'/opt/{name}']
    command += ['--ro-bind', __file__, '/smoke.py', '--setenv', 'HOME', '/home/tester', '--setenv', 'XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}', '--dir', f'/run/user/{os.getuid()}', '--setenv', 'SMOKE_WRAPPER', wrapper, '--chdir', '/home/tester/Work', '--', str(dbus), f'--config-file={dbus_config}', '--', str(Path(sys.executable).resolve()), '/smoke.py', 'inside']
    subprocess.run(command, check=True, timeout=120)
