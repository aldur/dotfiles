#!/usr/bin/env python3
"""Run with python3 test.py (requires bash and argc); curl is always mocked."""

import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


def mock_curl():
    args = sys.argv[2:]
    # Capture actual live argv on Linux, including the shell feeding curl.
    # sys.argv also checks curl's arguments on platforms without procfs.
    commands = [args]
    pid = os.getpid()
    while Path(f"/proc/{pid}/cmdline").exists():
        commands.append(Path(f"/proc/{pid}/cmdline").read_bytes().decode().split("\0"))
        if pid == int(os.environ["TELEGRAM_TEST_PID"]):
            break
        status = Path(f"/proc/{pid}/status").read_text().splitlines()
        pid = int(next(line.split()[1] for line in status if line.startswith("PPid:")))

    capture = {"args": args, "commands": commands, "config": sys.stdin.read()}
    Path(os.environ["CURL_CAPTURE"]).write_text(json.dumps(capture))
    exit_code = int(os.environ.get("CURL_EXIT_CODE", "0"))
    if "--write-out" in args:
        output = args[args.index("--write-out") + 1]
        # Emulate the supported write-out fields, including its output stream.
        stream = sys.stderr if output.startswith("%{stderr}") else sys.stdout
        fields = {
            "stderr": "",
            "http_code": "000" if exit_code else "200",
            "time_connect": "0.010000",
            "time_starttransfer": "0.020000",
            "time_total": "0.030000",
        }
        for field, value in fields.items():
            output = output.replace("%{" + field + "}", value)
        assert "%{" not in output, "unexpected curl write-out field"
        print(output.replace(r"\n", "\n"), end="", file=stream)
    if exit_code:
        print(f"curl: ({exit_code}) Failed to connect to api.telegram.org", file=sys.stderr)
    else:
        print('{"ok":true}')
    sys.exit(exit_code)


class TelegramTest(unittest.TestCase):
    TOKEN = "123456789:FAKE_token-for_debug_regression_012345"

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.capture = self.directory / "curl.json"
        mock = self.directory / "curl"
        mock.write_text(
            f"#!{shutil.which('bash')}\n"
            f"exec {shlex.quote(sys.executable)} {shlex.quote(str(Path(__file__).resolve()))}"
            ' --mock-curl "$@"\n'
        )
        mock.chmod(0o755)
        self.script = os.environ.get("TELEGRAM", str(Path(__file__).with_name("telegram.sh")))
        self.env = os.environ.copy()
        for key in ("DEBUG", "SHELLOPTS", "BASH_ENV", "BASHOPTS", "CURL_EXIT_CODE"):
            self.env.pop(key, None)
        self.env.update(
            BOT_TOKEN=self.TOKEN,
            CHAT_ID="1234",
            CURL_CAPTURE=str(self.capture),
            TELEGRAM_TEST_PID=str(os.getpid()),
            PATH=f"{self.directory}{os.pathsep}{os.environ['PATH']}",
        )

    def run_telegram(self, *args, debug=None, xtrace=False):
        self.capture.unlink(missing_ok=True)
        self.env.pop("DEBUG", None)
        if debug is not None:
            self.env["DEBUG"] = debug
        command = ["bash", *(["-x"] if xtrace else []), self.script, *args]
        result = subprocess.run(command, env=self.env, capture_output=True, text=True, timeout=10)
        self.assertNotIn(self.TOKEN, result.stderr)
        self.assertNotIn(self.TOKEN, result.stdout)
        if self.capture.exists():
            capture = json.loads(self.capture.read_text())
            for argv in [command, *capture["commands"]]:
                self.assertNotIn(self.TOKEN, " ".join(argv))
        return result

    def test_debug_and_xtrace_keep_token_out_of_logs_and_process_arguments(self):
        for endpoint, options in (
            ("sendMessage", []),
            ("sendPhoto", ["--photo", 'photo with "quotes".jpg']),
            ("sendVideo", ["--video", "video.mp4"]),
        ):
            for debug in (None, "", "1"):
                for xtrace in (False, True):
                    with self.subTest(endpoint=endpoint, debug=debug, xtrace=xtrace):
                        result = self.run_telegram(*options, "hello", debug=debug, xtrace=xtrace)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout, '{"ok":true}\n')
                        capture = json.loads(self.capture.read_text())
                        self.assertEqual(
                            capture["config"],
                            f'url = "https://api.telegram.org/bot{self.TOKEN}/{endpoint}"\n',
                        )
                        args = capture["args"]
                        self.assertEqual(args[args.index("--config") + 1], "-")
                        self.assertFalse({"-v", "--verbose", "--trace", "--trace-ascii"} & set(args))
                        if debug is not None:
                            self.assertIn("--write-out", args)
                            self.assertIn("HTTP 200", result.stderr)
                            self.assertIn("0.030000", result.stderr)
                        else:
                            self.assertNotIn("--write-out", args)
                            if not xtrace:
                                self.assertEqual(result.stderr, "")

    def test_curl_failure_keeps_diagnostics_and_exit_status(self):
        self.env["CURL_EXIT_CODE"] = "7"
        result = self.run_telegram("hello", debug="1", xtrace=True)
        self.assertEqual(result.returncode, 7)
        self.assertIn("HTTP 000", result.stderr)
        self.assertIn("Failed to connect", result.stderr)

    def test_invalid_token_is_rejected_without_logging_it(self):
        for suffix in ('"', "\n", "\r"):
            with self.subTest(suffix=repr(suffix)):
                self.env["BOT_TOKEN"] = self.TOKEN + suffix
                result = self.run_telegram("hello", debug="1", xtrace=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Telegram token format", result.stdout + result.stderr)
                self.assertFalse(self.capture.exists())

    def test_missing_token_explains_environment_input(self):
        self.env.pop("BOT_TOKEN")
        result = self.run_telegram("hello", debug="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("BOT_TOKEN environment variable", result.stdout + result.stderr)
        self.assertFalse(self.capture.exists())

    def test_token_option_is_no_longer_offered_or_accepted(self):
        result = self.run_telegram("--help")
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("--bot-token", result.stdout + result.stderr)
        self.assertIn("BOT_TOKEN", result.stdout + result.stderr)
        for option in ("--bot-token", "-t"):
            with self.subTest(option=option):
                result = self.run_telegram(option, "removed-option", "hello", debug="1")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.capture.exists())


if __name__ == "__main__":
    if sys.argv[1:2] == ["--mock-curl"]:
        mock_curl()
    else:
        unittest.main()
