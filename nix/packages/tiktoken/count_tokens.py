#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Approximate the number of tokens."""

import sys

import tiktoken


def main():
    encoder = tiktoken.get_encoding("o200k_base")
    result = encoder.encode(sys.stdin.read())
    print(len(result))


if __name__ == "__main__":
    main()
