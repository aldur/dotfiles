"""Print each skill name that more than one source loads into Claude Code."""

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


def sources(config_dir):
    found = {}

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
    if isinstance(enabled, dict) and isinstance(installed, dict):
        for plugin, on in enabled.items():
            entries = installed.get(plugin)
            if on is not True or not plugin.isprintable() or not isinstance(entries, list):
                continue
            # Project-scope installations load only in their project.
            names = set()
            for entry in entries:
                if isinstance(entry, dict) and entry.get("scope") == "user" and isinstance(entry.get("installPath"), str):
                    names |= skill_names(Path(entry["installPath"]) / "skills")
            add(names, f"plugin {plugin}")

    return found


if __name__ == "__main__":
    for name, where in sorted(sources(Path(sys.argv[1])).items()):
        if len(where) > 1:
            print(f"{name}: {', '.join(where)}")
