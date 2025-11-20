#!/usr/bin/env python3
"""Fix Guide-type entries in Dash docset to point to the main heading anchor."""

import sqlite3
import sys
from pathlib import Path

from bs4 import BeautifulSoup


def main() -> None:
    """Fix guide anchors in the Dash docset database."""
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <docset_path>", file=sys.stderr)
        sys.exit(1)

    docset_path = Path(sys.argv[1])
    db_path = docset_path / "Contents/Resources/docSet.dsidx"
    docs_path = docset_path / "Contents/Resources/Documents"

    if not db_path.exists():
        print(f"Database not found: {db_path}", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute(
        "SELECT name, path FROM searchIndex WHERE type='Guide' AND path NOT LIKE '%#%'"
    )
    entries = cursor.fetchall()

    for name, path in entries:
        html_file = docs_path / path
        if not html_file.exists():
            continue

        with open(html_file, "r", encoding="utf-8") as f:
            soup = BeautifulSoup(f.read(), "lxml")

        h1 = soup.find("h1")
        if h1:
            section = h1.find_parent("section")
            if section and section.get("id"):
                anchor_id = section["id"]
                new_path = f"{path}#{anchor_id}"
                cursor.execute(
                    "UPDATE searchIndex SET path=? WHERE name=? AND type='Guide' AND path=?",
                    (new_path, name, path),
                )

    conn.commit()
    conn.close()


if __name__ == "__main__":
    main()
