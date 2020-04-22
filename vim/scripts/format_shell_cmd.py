#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Credits:
https://www.bbkane.com/2020/04/14/Long-Shell-Oneliners-Without-the-Pain.html
"""

import argparse
import sys
import typing as t

__author__ = "Benjamin Kane"
__version__ = "0.1.0"
__doc__ = f"""
Pretty-print simple Bash command from one line of stdin
Examples:
    echo 'echo "hi there" | awk "{{print $1}}"' | {sys.argv[0]}
Help:
Please see Benjamin Kane for help.
"""


def parse_args(*args, **kwargs):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    return parser.parse_args(*args, **kwargs)


# need to tokenize into words, strings, pipes, options
# strings are surrounded by quotes - and can have nested quotes
# pipes are |
# options start with -
# Test with: python3 -m doctest  format_shell.py


class Kind:
    UNSET = "UNSET"
    PIPE = "PIPE"
    OPTION = "OPTION"
    SINGLE_QUOTE_STRING = "SINGLE_QUOTE_STRING"
    DOUBLE_QUOTE_STRING = "DOUBLE_QUOTE_STRING"
    CMD = "CMD"


class Token(t.NamedTuple):
    text: str
    kind: Kind


def tokenize(expr):
    start = 0
    end = 0
    len_expr = len(expr)  # cache constant value
    while True:
        # eat whitespace
        while end < len_expr and expr[end].isspace():
            start += 1
            end += 1
        if end == len_expr:
            return

        if expr[end] == "|":
            end += 1
            yield Token(expr[start:end], Kind.PIPE)
            start = end
        elif expr[end] == "-":
            while end < len_expr and not expr[end].isspace():
                end += 1
            yield Token(expr[start:end], Kind.OPTION)
            start = end
        elif expr[end] == '"':
            while True:
                end += 1
                if end == len_expr:
                    raise ValueError(f"Double quote at column {start} unmatched")
                if expr[end] == '"':
                    break
            end += 1
            yield Token(expr[start:end], Kind.DOUBLE_QUOTE_STRING)
            start = end
        elif expr[end] == "'":
            while True:
                end += 1
                if end == len_expr:
                    raise ValueError(f"Single quote at column {start} unmatched")
                if expr[end] == "'":
                    break
            end += 1
            yield Token(expr[start:end], Kind.SINGLE_QUOTE_STRING)
            start = end
        else:  # not space, not anything else, must be cmd
            while end < len_expr and not expr[end].isspace():
                end += 1
            yield Token(expr[start:end], Kind.CMD)
            start = end


def print_cmd(tokens: t.Iterable[Token]):
    for token in tokens:
        if token.kind == Kind.PIPE:
            print("\\\n| ", end="")
        elif token.kind == Kind.OPTION:
            print(f"\\\n    {token.text} ", end="")
        elif token.kind in (
            Kind.CMD,
            Kind.DOUBLE_QUOTE_STRING,
            Kind.SINGLE_QUOTE_STRING,
        ):
            print(f"{token.text} ", end="")
        else:
            raise ValueError(f"Unknown token kind: {token!r}")
    print()


def main():
    # get --help
    parse_args()
    command = sys.stdin.readline()
    print_cmd(tokenize(command))


if __name__ == "__main__":
    main()
