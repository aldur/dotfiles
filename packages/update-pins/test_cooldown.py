"""Offline tests for cooldown.py. A table replaces the network."""

import sys
import unittest
from datetime import datetime, timezone

import cooldown

NOW = datetime(2026, 11, 11, 12, tzinfo=timezone.utc)
REPO = "https://api.github.com/repos/o/r"
OLD, PIN, COOLED, FRESH = "a" * 40, "b" * 40, "c" * 40, "d" * 40


def spec(**fields):
    base = {"days": 3, "type": "github", "owner": "o", "repo": "r", "args": ""}
    return {**base, "rev": PIN, "tag": None, "version": "1.0", **fields}


class Cooldown(unittest.TestCase):
    def select(self, spec, pages):
        seen = []

        def fetch(url):
            seen.append(url)
            return pages[url]

        cooldown.fetch = fetch
        return cooldown.select(spec, NOW), seen

    def test_branch_takes_the_head_of_three_days_ago(self):
        activity = f"{REPO}/activity?ref=refs%2Fheads%2Fmain&per_page=100"
        pages = {
            REPO: ({"default_branch": "main"}, None),
            activity: ([{"after": FRESH, "timestamp": "2026-11-10T00:00:00Z"}], "next"),
            "next": (
                [
                    {"after": COOLED, "timestamp": "2026-11-08T11:59:59Z"},
                    {"after": OLD, "timestamp": "2026-11-01T00:00:00Z"},
                ],
                None,
            ),
            f"{REPO}/compare/{PIN}...{COOLED}": ({"status": "ahead"}, None),
        }
        selected, _ = self.select(spec(args="--version=branch"), pages)
        self.assertEqual(selected, f"branch={COOLED}")

    def test_branch_does_not_go_back(self):
        activity = f"{REPO}/activity?ref=refs%2Fheads%2Fnext&per_page=100"
        pages = {
            activity: ([{"after": OLD, "timestamp": "2026-11-01T00:00:00Z"}], None),
            f"{REPO}/compare/{PIN}...{OLD}": ({"status": "behind"}, None),
        }
        selected, seen = self.select(spec(args="--version=branch=next --test"), pages)
        self.assertIsNone(selected)
        self.assertNotIn(REPO, seen)

    def test_branch_with_only_fresh_pushes(self):
        activity = f"{REPO}/activity?ref=refs%2Fheads%2Fmain&per_page=100"
        pages = {
            REPO: ({"default_branch": "main"}, None),
            activity: ([{"after": FRESH, "timestamp": "2026-11-10T00:00:00Z"}], None),
        }
        self.assertIsNone(self.select(spec(args="--version=branch"), pages)[0])

    def release(self, tag, published, **fields):
        return {"tag_name": tag, "published_at": published, "draft": False, "prerelease": False, **fields}

    def test_release_skips_the_fresh_one(self):
        releases = [
            self.release("v1.3", "2026-11-10T00:00:00Z"),
            self.release("v1.2-rc1", "2026-11-05T00:00:00Z", prerelease=True),
            self.release("v1.1", "2026-11-02T00:00:00Z"),
            self.release("v1.0", "2026-10-01T00:00:00Z"),
        ]
        pages = {f"{REPO}/releases?per_page=100": (releases, None)}
        self.assertEqual(self.select(spec(tag="v1.0"), pages)[0], "1.1")
        self.assertIsNone(self.select(spec(tag="v1.1", version="1.1"), pages)[0])

    def test_release_stops_without_releases(self):
        pages = {f"{REPO}/releases?per_page=100": ([], None)}
        with self.assertRaises(SystemExit):
            self.select(spec(tag="v1.0"), pages)

    def test_release_applies_the_version_regex(self):
        releases = [
            self.release("docs-9", "2026-11-03T00:00:00Z"),
            self.release("v1.1", "2026-11-02T00:00:00Z"),
        ]
        pages = {f"{REPO}/releases?per_page=100": (releases, None)}
        args = "--version-regex 'v(\\d+\\.\\d+)$'"
        self.assertEqual(self.select(spec(tag="v1.0", args=args), pages)[0], "1.1")

    def test_unknown_source_stops(self):
        unknown = {"days": 3, "type": "unknown", "url": "https://example.org/x.tar.gz", "args": "", "version": "1"}
        with self.assertRaises(SystemExit):
            self.select(unknown, {})

    def test_pypi_uses_the_upload_time(self):
        def files(uploaded, yanked=False):
            return [{"upload_time_iso_8601": uploaded, "yanked": yanked}]

        data = {
            "releases": {
                "0.2.1": files("2026-10-01T00:00:00Z"),
                "0.10.0": files("2026-11-02T00:00:00.123456Z"),
                "0.10.1": files("2026-11-03T00:00:00Z", yanked=True),
                "0.11.0": files("2026-11-10T00:00:00Z"),
                "1.0.0rc1": files("2026-11-01T00:00:00Z"),
            }
        }
        pages = {"https://pypi.org/pypi/pkg/json": (data, None)}
        pin = {"days": 3, "type": "pypi", "name": "pkg", "args": ""}
        self.assertEqual(self.select({**pin, "version": "0.2.1"}, pages)[0], "0.10.0")
        self.assertIsNone(self.select({**pin, "version": "0.10.0"}, pages)[0])


if __name__ == "__main__":
    unittest.main(argv=sys.argv[:1])
