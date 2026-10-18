"""Exercise the packaged CLI, including its default config and both fix modes."""

import pathlib
import subprocess
import sys
import tempfile


command = sys.argv[1:]


def run(directory, *args, input=None):
    result = subprocess.run(
        [*command, *args], cwd=directory, input=input, capture_output=True, text=True
    )
    assert result.returncode in (0, 1), result.stdout + result.stderr
    return result


# These should still produce diagnostics, but neither fix mode may rewrite them.
diagnostic_only = {
    "MD004": "- First\n\n+ Second\n",
    "MD011": "(label)[https://example.com]\n",
    "MD018": "#Heading\n",
    "MD020": "#Heading#\n",
    "MD037": "Before * word * after.\n",
    "MD051": "# Heading\n\n[link](#Heading)\n",
}

preserve = {
    "heading punctuation": "# Stop!\n\n## Details:\n",
    "shell prompts and tabs": "# Code\n\n```sh\n$ printf hi\n```\n\n```make\nall:\n\techo hi\n```\n",
    "list numbering": "# Steps\n\n7. First\n8. Second\n",
    "inline code spaces": "# Code\n\nBefore `  padded  ` and `trailing ` after.\n",
    "references": "# Links\n\n[link][used]\n\n[used]: https://example.com\n[used]: https://example.org\n[unused]: https://example.net\n",
    "link labels and titles": '# Links\n\n[Descriptive label](https://example.com "A title")\n',
    "HTML and bare URLs": "# HTML\n\n<details>\n<summary>More</summary>\n\nhttps://example.com\n\n</details>\n",
    "hard line breaks": "# Breaks\n\nFirst line  \nSecond line\n",
    "code trailing spaces": "# Code\n\n```text\npadded   \n```\n",
    **diagnostic_only,
}

fix = {
    "heading spacing": ("# Stop!\n## Details:\n", "# Stop!\n\n## Details:\n"),
    "emphasis style": (
        "# Style\n\n*one* and _two_, **three** and __four__.\n",
        "# Style\n\n*one* and *two*, **three** and **four**.\n",
    ),
    "blockquote spacing": (
        "> Before\n> # Heading\n> After\n",
        "> Before\n>\n> # Heading\n>\n> After\n",
    ),
    "ordinary trailing spaces": (
        "# Spaces\n\nTrailing   \nNext\n",
        "# Spaces\n\nTrailing\nNext\n",
    ),
}

with tempfile.TemporaryDirectory(prefix="markdownlint-formatting-") as directory:
    for extension in ("md", "mdx"):
        path = pathlib.Path(directory, "fixture." + extension)
        for rule, text in diagnostic_only.items():
            path.write_text(text)
            result = run(directory, str(path))
            assert rule in result.stderr, (rule, result.stderr)
            assert path.read_text() == text, rule

        cases = {**{name: (text, text) for name, text in preserve.items()}, **fix}
        for name, (before, expected) in cases.items():
            path.write_text(before)
            run(directory, "--fix", str(path))
            actual = path.read_text()
            assert actual == expected, (extension, name, actual, expected)
            result = run(directory, "--format", input=before)
            assert result.stdout == expected, (extension, name, result.stdout, expected)

print("Markdownlint preserves authored content, keeps diagnostics, and applies style fixes.")
