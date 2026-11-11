"""Select the newest upstream state that is older than the cooldown.

Read the `cooldown` object of one `updatePins` leg from stdin. Print the
nix-update `--version` argument that selects that state. Print nothing if
no such state is newer than the pin.

The ages come from the servers: the push time of a branch, the publication
time of a GitHub release, the upload time of a PyPI file. The author of a
commit sets the commit date, so this script does not use it.
"""

import json
import os
import re
import shlex
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

GITHUB = "https://api.github.com"


def fetch(url):
    """Return the JSON body and the URL of the next page."""
    headers = {"Accept": "application/json", "User-Agent": "update-pins"}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token and url.startswith(GITHUB + "/"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            following = re.search(r'<([^>]+)>; rel="next"', response.headers.get("Link", ""))
            return json.load(response), following and following.group(1)
    except urllib.error.URLError as error:
        raise SystemExit(f"cooldown: {url}: {error}") from None


def moment(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def option(args, *names):
    """Return the value of a nix-update option, in both of its spellings."""
    for index, arg in enumerate(args):
        for name in names:
            if arg == name and index + 1 < len(args):
                return args[index + 1]
            if arg.startswith(name + "="):
                return arg[len(name) + 1 :]
    return None


def branch(spec, name, cutoff):
    repo = f"{GITHUB}/repos/{spec['owner']}/{spec['repo']}"
    name = name or fetch(repo)[0]["default_branch"]
    ref = urllib.parse.quote(f"refs/heads/{name}", safe="")
    url = f"{repo}/activity?ref={ref}&per_page=100"
    head = None
    while url and head is None:
        page, url = fetch(url)
        head = next((e["after"] for e in page if moment(e["timestamp"]) <= cutoff), None)
    if head is None or head == spec["rev"]:
        return None
    # The pin can be newer than the selected head. Do not go back.
    status = fetch(f"{repo}/compare/{spec['rev']}...{head}")[0]["status"]
    if status not in ("ahead", "diverged"):
        return None
    if not re.fullmatch(r"[0-9a-f]{40}", head) or not int(head, 16):
        raise SystemExit(f"cooldown: bad commit from the activity API: {head!r}")
    return f"branch={head}"


def release(spec, regex, cutoff):
    repo = f"{GITHUB}/repos/{spec['owner']}/{spec['repo']}"
    tag = spec["tag"] or ""
    prefix = tag.removesuffix(spec["version"]) if tag.endswith(spec["version"]) else ""

    def version(name):
        if regex:
            match = re.match(regex, name)
            return match and next((group for group in match.groups() if group), None)
        return name.removeprefix(prefix) if name.startswith(prefix) else None

    releases, _ = fetch(f"{repo}/releases?per_page=100")
    published = {r["tag_name"]: moment(r["published_at"]) for r in releases if r["published_at"]}
    final = [
        r["tag_name"]
        for r in releases
        if not r["draft"] and not r["prerelease"] and r["tag_name"] in published and version(r["tag_name"])
    ]
    if not final:
        # Without this stop, a repository that only has tags is never bumped.
        raise SystemExit(
            f"cooldown: {spec['owner']}/{spec['repo']} has no GitHub release. "
            "Set `passthru.updatePin.cooldown = false` to bump it without a cooldown."
        )
    old = [name for name in final if published[name] <= cutoff]
    if not old:
        return None
    newest = max(old, key=lambda name: published[name])
    if tag in published and published[newest] <= published[tag]:
        return None
    return version(newest)


def pypi(spec, cutoff):
    def key(version):
        return tuple(int(part) for part in version.split("."))

    data, _ = fetch(f"https://pypi.org/pypi/{spec['name']}/json")
    old = []
    for version, files in data["releases"].items():
        files = [f for f in files if not f["yanked"]]
        # Final releases only.
        if not files or not re.fullmatch(r"\d+(\.\d+)*", version):
            continue
        if min(moment(f["upload_time_iso_8601"]) for f in files) <= cutoff:
            old.append(version)
    if not old:
        return None
    newest = max(old, key=key)
    current = spec["version"]
    if re.fullmatch(r"\d+(\.\d+)*", current) and key(newest) <= key(current):
        return None
    return newest


def select(spec, now):
    cutoff = now - timedelta(days=spec["days"])
    args = shlex.split(spec["args"])
    if spec["type"] == "pypi":
        return pypi(spec, cutoff)
    if spec["type"] != "github":
        raise SystemExit(
            f"cooldown: cannot find the age of {spec['url']}. "
            "Set `passthru.updatePin.cooldown = false` to bump it without a cooldown."
        )
    mode = option(args, "--version") or ""
    if mode == "branch" or mode.startswith("branch="):
        return branch(spec, mode[len("branch=") :] or None, cutoff)
    return release(spec, option(args, "--version-regex", "-vr"), cutoff)


def main():
    selected = select(json.load(sys.stdin), datetime.now(timezone.utc))
    if selected is None:
        return
    # The caller passes this text to a shell.
    if not re.fullmatch(r"[0-9A-Za-z._+=-]+", selected):
        raise SystemExit(f"cooldown: bad version from upstream: {selected!r}")
    print(f"--version={selected}")


if __name__ == "__main__":
    main()
