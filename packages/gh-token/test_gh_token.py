import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import requests

import gh_token


class ExchangeTests(unittest.TestCase):
    def setUp(self):
        self.post = patch.object(gh_token.requests, "post")
        self.mock = self.post.start()
        self.addCleanup(self.post.stop)

    def respond(self, content):
        response = requests.Response()
        response.status_code = 200
        response._content = content
        self.mock.return_value = response

    def test_form_body_and_timeout(self):
        self.respond(b'{"access_token":"access","refresh_token":"next","expires_in":3600}')
        self.assertEqual(gh_token.exchange("token+&=")["access_token"], "access")
        args, kwargs = self.mock.call_args
        self.assertEqual(args, (gh_token.ENDPOINT,))
        self.assertEqual(kwargs["data"], {
            "grant_type": "refresh_token",
            "client_id": gh_token.CLIENT_ID,
            "client_secret": gh_token.CLIENT_SECRET,
            "refresh_token": "token+&=",
        })
        self.assertEqual(kwargs["headers"], {"Accept": "application/json"})
        self.assertEqual(kwargs["timeout"], 30)
        self.assertFalse(kwargs["allow_redirects"])

    def test_oauth_error_does_not_print_response_tokens(self):
        self.respond(b'{"error":"bad_refresh_token","error_description":"secret-token"}')
        with self.assertRaises(gh_token.TokenError) as raised:
            gh_token.exchange("secret-token")
        self.assertIn("bad_refresh_token", str(raised.exception))
        self.assertNotIn("secret-token", str(raised.exception))

    def test_malformed_json(self):
        for content in (b"not JSON", b"[]", b"{}", b'{"access_token":"a","refresh_token":"r"}'):
            self.respond(content)
            with self.assertRaises(gh_token.TokenError):
                gh_token.exchange("refresh")

    def test_http_error_is_not_retried(self):
        self.respond(b"secret")
        self.mock.return_value.status_code = 500
        with self.assertRaisesRegex(gh_token.TokenError, "HTTP 500"):
            gh_token.exchange("refresh")
        self.assertEqual(self.mock.call_count, 1)

    def test_redirect_is_an_error(self):
        self.respond(b"")
        self.mock.return_value.status_code = 307
        with self.assertRaisesRegex(gh_token.TokenError, "HTTP 307"):
            gh_token.exchange("refresh")

    def test_network_error_is_not_retried_or_printed(self):
        self.mock.side_effect = requests.Timeout("secret-token")
        with self.assertRaisesRegex(gh_token.TokenError, "no automatic retry") as raised:
            gh_token.exchange("secret-token")
        self.assertNotIn("secret-token", str(raised.exception))
        self.assertEqual(self.mock.call_count, 1)


class StateTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        key = self.root / "identity"
        subprocess.run(["age-keygen", "-o", str(key)], check=True, capture_output=True)
        recipient = subprocess.check_output(["age-keygen", "-y", str(key)])
        recipients = self.root / "recipients"
        recipients.write_bytes(recipient)
        environment = patch.dict(os.environ, {
            "XDG_STATE_HOME": str(self.root),
            "GH_TOKEN_IDENTITIES_FILE": str(key),
            "GH_TOKEN_RECIPIENTS_FILE": str(recipients),
        })
        environment.start()
        self.addCleanup(environment.stop)
        self.addCleanup(os.umask, os.umask(0o077))
        self.path = self.root / "gh-token/credentials.age"
        self.response = {"access_token": "new-access", "refresh_token": "new-refresh", "expires_in": 3600}

    def run_cli(self, args=(), input_text="", response=None, tty=False):
        output, errors = io.StringIO(), io.StringIO()
        source = io.StringIO(input_text)
        source.isatty = lambda: tty
        with (
            patch("sys.argv", ["gh-token", *args]),
            patch("sys.stdin", source),
            patch("sys.stdout", output),
            patch("sys.stderr", errors),
            patch.object(gh_token, "exchange", return_value=response or self.response) as exchange,
        ):
            status = gh_token.main()
        return status, output.getvalue(), errors.getvalue(), exchange

    def decrypt(self, path=None):
        return json.loads(gh_token.age([
            "-d", "-i", os.environ["GH_TOKEN_IDENTITIES_FILE"], str(path or self.path),
        ]))

    def assert_encrypted(self):
        for path in self.path.parent.iterdir():
            content = path.read_bytes()
            for secret in (b"seed-refresh", b"new-access", b"new-refresh"):
                self.assertNotIn(secret, content)
        self.assertTrue(self.path.read_bytes().startswith(b"age-encryption.org/v1\n"))
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.path.parent.stat().st_mode), 0o700)

    def initialize(self):
        status, output, errors, exchange = self.run_cli(["init"], "seed-refresh\nentry notes\n")
        self.assertEqual(status, 0)
        self.assertEqual(output, "")
        self.assertEqual(errors, "")
        exchange.assert_not_called()

    def test_import_is_encrypted_without_a_network_request(self):
        self.initialize()
        self.assertEqual(self.decrypt(), {"refresh_token": "seed-refresh"})
        self.assert_encrypted()

    def test_first_use_saves_both_tokens_before_printing_only_access(self):
        self.initialize()
        with patch.object(gh_token.time, "time", return_value=1000):
            status, output, errors, exchange = self.run_cli()
        self.assertEqual((status, output, errors), (0, "new-access\n", ""))
        exchange.assert_called_once_with("seed-refresh")
        credentials = self.decrypt()
        self.assertEqual(credentials["refresh_token"], "new-refresh")
        self.assertEqual(credentials["access_token"], "new-access")
        self.assertEqual(credentials["expires_at"], 4600)
        self.assert_encrypted()

    def test_valid_access_token_is_reused_without_rewriting_state(self):
        self.initialize()
        self.run_cli()
        before = self.path.read_bytes()
        status, output, errors, exchange = self.run_cli()
        self.assertEqual((status, output, errors), (0, "new-access\n", ""))
        exchange.assert_not_called()
        self.assertEqual(self.path.read_bytes(), before)

    def test_near_expiry_uses_the_rotated_refresh_token(self):
        self.initialize()
        with patch.object(gh_token.time, "time", return_value=1000):
            self.run_cli()
        with patch.object(gh_token.time, "time", return_value=4540):
            status, _, _, exchange = self.run_cli()
        self.assertEqual(status, 0)
        exchange.assert_called_once_with("new-refresh")

    def test_existing_credentials_are_not_replaced_by_import(self):
        self.initialize()
        before = self.path.read_bytes()
        status, output, errors, exchange = self.run_cli(["init"], "different-token")
        self.assertEqual((status, output), (1, ""))
        self.assertIn("credentials already exist", errors)
        exchange.assert_not_called()
        self.assertEqual(self.path.read_bytes(), before)

    def test_missing_state_does_not_refresh_or_prompt(self):
        status, output, errors, exchange = self.run_cli()
        self.assertEqual((status, output), (1, ""))
        self.assertIn("gh-token init", errors)
        exchange.assert_not_called()

    def test_write_failure_does_not_print_access_token(self):
        self.initialize()
        before = self.path.read_bytes()
        with patch.object(gh_token.os, "replace", side_effect=OSError("disk failure")):
            status, output, errors, _ = self.run_cli()
        self.assertEqual((status, output), (1, ""))
        self.assertIn("recover the encrypted replacement", errors)
        self.assertEqual(self.path.read_bytes(), before)
        pending = [p for p in self.path.parent.iterdir() if p.name not in {"credentials.age", "lock"}]
        self.assertEqual(len(pending), 1)
        self.assertIn(str(pending[0]), errors)
        self.assertEqual(self.decrypt(pending[0])["refresh_token"], "new-refresh")
        self.assert_encrypted()

    def test_decryption_failure_does_not_refresh(self):
        self.initialize()
        self.path.write_bytes(b"invalid age file")
        status, output, _, exchange = self.run_cli()
        self.assertEqual((status, output), (1, ""))
        exchange.assert_not_called()

    def test_invalid_state_does_not_refresh(self):
        self.initialize()
        gh_token.save(self.path, {"refresh_token": "seed-refresh", "access_token": "access", "expires_at": "later"})
        status, output, errors, exchange = self.run_cli()
        self.assertEqual((status, output), (1, ""))
        self.assertIn("invalid access token or expiry", errors)
        exchange.assert_not_called()

    def test_invalid_recipients_do_not_consume_refresh_token(self):
        self.initialize()
        before = self.path.read_bytes()
        with patch.dict(os.environ, {"GH_TOKEN_RECIPIENTS_FILE": str(self.root / "missing")}):
            status, output, _, exchange = self.run_cli()
        self.assertEqual((status, output), (1, ""))
        exchange.assert_not_called()
        self.assertEqual(self.path.read_bytes(), before)

    def test_empty_input_does_not_call_github(self):
        status, output, errors, exchange = self.run_cli(["init"])
        self.assertEqual(status, 1)
        self.assertEqual(output, "")
        self.assertIn("provide one refresh token", errors)
        exchange.assert_not_called()

    def test_hidden_prompt(self):
        with patch("getpass.getpass", return_value="seed-refresh") as prompt:
            status, output, errors, exchange = self.run_cli(["init"], tty=True)
        self.assertEqual((status, output, errors), (0, "", ""))
        prompt.assert_called_once()
        exchange.assert_not_called()
        self.assertEqual(self.decrypt(), {"refresh_token": "seed-refresh"})

    def test_concurrent_calls_exchange_only_once(self):
        self.initialize()
        calls = self.root / "calls"
        script = '''
import sys
import gh_token

calls_path = sys.argv[1]
def exchange(refresh):
    with open(calls_path, "a") as calls:
        calls.write(refresh + "\\n")
    return {"access_token": "new-access", "refresh_token": "new-refresh", "expires_in": 3600}

gh_token.exchange = exchange
sys.argv = ["gh-token"]
sys.exit(gh_token.main())
'''
        processes = [subprocess.Popen(
            [sys.executable, "-c", script, str(calls)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ) for _ in range(3)]
        try:
            for process in processes:
                output, errors = process.communicate(timeout=15)
                self.assertEqual((process.returncode, output, errors), (0, b"new-access\n", b""))
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()
        self.assertEqual(calls.read_text(), "seed-refresh\n")
        self.assert_encrypted()


class FishTests(unittest.TestCase):
    def run_shortcut(self, **environment):
        return subprocess.run([
            "fish", "--no-config", "-c",
            'source "$GHS_FUNCTION"; set -gx GH_TOKEN outer; '
            'ghs pr view "two words"; set -l result $status; '
            'echo "parent:$GH_TOKEN"; exit $result',
        ], capture_output=True, text=True, env={
            **os.environ,
            "PATH": os.environ["FISH_TEST_BIN"] + os.pathsep + os.environ["PATH"],
            **environment,
        })

    def test_command_arguments_environment_and_exit_status(self):
        result = self.run_shortcut(GH_TEST_STATUS="23")
        self.assertEqual(result.returncode, 23)
        command, parent = result.stdout.splitlines()
        self.assertEqual(json.loads(command), {"token": "cached-access", "args": ["pr", "view", "two words"]})
        self.assertEqual(parent, "parent:outer")
        self.assertEqual(result.stderr, "")

    def test_failed_decryption_does_not_run_gh(self):
        result = self.run_shortcut(TOKEN_STATUS="17")
        self.assertEqual(result.returncode, 17)
        self.assertEqual(result.stdout, "parent:outer\n")

    def test_empty_token_does_not_run_gh(self):
        result = self.run_shortcut(TOKEN_OUTPUT="")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "parent:outer\n")
        self.assertIn("no access token", result.stderr)


if __name__ == "__main__":
    unittest.main()
