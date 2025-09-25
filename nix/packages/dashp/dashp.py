#!/usr/bin/env python3

"""
Merge multiple Dash docsets and search them with fzf.
"""

import contextlib
import logging
import sqlite3
import subprocess
import sys
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")


def merge_docsets(docsets: list[Path]) -> sqlite3.Connection:
    with sqlite3.connect(":memory:") as db:
        cursor = db.cursor().execute(
            "CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);"
        )

        for docset in docsets:
            docset_db_path = docset / "Contents/Resources/docSet.dsidx"
            if not docset_db_path.exists():
                logging.warning("Database not found for docset: %s", docset)
                continue

            with contextlib.closing(
                sqlite3.connect(f"file:{docset_db_path}?mode=ro", uri=True)
            ) as docset_db:
                docset_cursor = docset_db.cursor().execute(
                    "SELECT name, type, path FROM searchIndex"
                )

                rows: list[tuple[str, str, str]] = docset_cursor.fetchall()
                for name, entry_type, path in rows:
                    prefixed_path = docset / "Contents/Resources/Documents" / path
                    cursor = cursor.execute(
                        "INSERT INTO searchIndex (name, type, path) VALUES (?, ?, ?)",
                        (name, entry_type, str(prefixed_path)),
                    )

        return db


def launch_fzf(db: sqlite3.Connection) -> str | None:
    rows: list[tuple[str, str, str]] = (
        db.cursor().execute("SELECT name, type, path FROM searchIndex").fetchall()
    )
    fzf_input = "\n".join(
        f"{name} ({entry_type})\t{path}" for name, entry_type, path in rows
    )

    try:
        fzf_process = subprocess.run(
            ["fzf", "--with-nth", "1", "--delimiter", "\t", "--accept-nth", "-1"],
            input=fzf_input,
            capture_output=True,
            text=True,
            check=True,
        )

        if selected_line := fzf_process.stdout.strip():
            return selected_line
    except FileNotFoundError:
        logging.error("FZF is not installed. Please install FZF to use this script.")
    except subprocess.CalledProcessError:
        logging.error("FZF failed to run.")

    return None


def main() -> None:
    if len(sys.argv) < 2:
        logging.error("Usage: %s <docset1> <docset2> ...", sys.argv[0])
        sys.exit(1)

    docsets = [
        Path(arg) for arg in sys.argv[1:] if arg.removesuffix("/").endswith(".docset")
    ]

    if not docsets:
        logging.error("No docsets provided.")
        sys.exit(1)

    with contextlib.closing(merge_docsets(docsets)) as db:
        if selected_path := launch_fzf(db):
            print(selected_path)
            sys.exit(0)

        sys.exit(1)


if __name__ == "__main__":
    main()
