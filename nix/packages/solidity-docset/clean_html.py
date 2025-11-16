#!/usr/bin/env python3
"""Remove navigation elements from HTML files to make them cleaner for Dash."""

import sys
from bs4 import BeautifulSoup


def main() -> None:
    """Clean navigation elements from an HTML file."""
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <html_file>", file=sys.stderr)
        sys.exit(1)

    html_file = sys.argv[1]

    with open(html_file, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), "lxml")

    # Remove navigation elements that clutter the display
    for element in soup.select(
        ".wy-nav-side, .wy-nav-top, .rst-versions, .headerlink, "
        ".w3c-header, .wy-breadcrumbs"
    ):
        element.decompose()

    # Remove the navigation container and expand content to full width
    for element in soup.select(".wy-nav-content-wrap"):
        element.unwrap()

    for element in soup.select(".wy-nav-content"):
        if element.get("style"):
            element["style"] = ""
        element["style"] = "max-width: none; margin: 0;"

    # Write back
    with open(html_file, "w", encoding="utf-8") as f:
        f.write(str(soup))


if __name__ == "__main__":
    main()
