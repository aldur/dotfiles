"""Print the skills that Claude Code loads more than once and the enabled plugins that are not installed."""

import json
from pathlib import Path
import sys


def load(path):
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def skill_names(directory):
    return {path.parent.name for path in directory.glob("*/SKILL.md")}


def check(config_dir):
    found = {}
    missing = []

    def add(names, source):
        for name in names:
            if isinstance(name, str) and name.isprintable():
                found.setdefault(name, []).append(source)

    add(skill_names(config_dir / "skills"), "~/.claude/skills")

    for manifest in (config_dir / "skills" / "synced").glob("*/manifest.json"):
        skills = load(manifest).get("skills")
        if isinstance(skills, list):
            add({s.get("name") for s in skills if isinstance(s, dict)}, "claude.ai sync")

    enabled = load(config_dir / "settings.json").get("enabledPlugins")
    installed = load(config_dir / "plugins" / "installed_plugins.json").get("plugins")
    if not isinstance(installed, dict):
        installed = {}
    if isinstance(enabled, dict):
        for plugin, on in enabled.items():
            # Claude Code ships the @builtin plugins and does not record them.
            if on is not True or not plugin.isprintable() or plugin.endswith("@builtin"):
                continue
            entries = installed.get(plugin)
            paths = []
            for entry in entries if isinstance(entries, list) else []:
                # Project-scope installations load only in their project.
                if isinstance(entry, dict) and entry.get("scope") == "user" and isinstance(entry.get("installPath"), str):
                    paths.append(entry["installPath"])
            if not paths:
                missing.append(plugin)
            add(set().union(*(skill_names(Path(path) / "skills") for path in paths)), f"plugin {plugin}")

    return {name: where for name, where in found.items() if len(where) > 1}, sorted(missing)


if __name__ == "__main__":
    duplicates, missing = check(Path(sys.argv[1]))
    if duplicates:
        print("Claude Code loads these skills more than once:")
        for name, where in sorted(duplicates.items()):
            print(f"  {name}: {', '.join(where)}")
    if missing:
        print("These plugins are enabled but not installed. Install each with `claude plugin install <plugin>`:")
        for plugin in missing:
            print(f"  {plugin}")
