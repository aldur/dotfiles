#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Parse natural language into dates.
Also, provides a command to edit a specific wiki.vim journal date.

Requires: https://github.com/alvinwan/timefhuman

```bash
pip3 install timefhuman
```
"""

import pynvim
import collections

from os.path import expanduser, join


DATE_FORMAT = "%Y-%m-%d"

__author__ = "Adriano Di Luzio <adrianodl@hotmail.it>"


@pynvim.plugin
class NaturalDates(object):
    def __init__(self, nvim):
        self.nvim = nvim

    @pynvim.function("NaturalDate", sync=True)
    def natural_date(self, args):
        try:
            from timefhuman import timefhuman
        except ImportError:
            self.nvim.err_write("Can't import `timefhuman`, exiting...")
            return -1

        nld = " ".join(args)
        dates = timefhuman(nld)

        if not dates:
            return -1

        if isinstance(dates, collections.abc.Iterable):
            d, *_ = dates
        else:
            d = dates

        return d.date().strftime(DATE_FORMAT)

    @pynvim.command("WikiJournalDate", range="", nargs="*", sync=True)
    def command_handler(self, args, range):
        wiki_path = expanduser(self.nvim.vars["wiki_root"])
        if not wiki_path:
            self.nvim.err_write("Cannot find `g:wiki_path`.")
            return

        journal_path = join(wiki_path, "journal")
        extension = self.nvim.vars.get("wiki_link_extension", None) or 'md'

        d = self.natural_date(args)
        if d == -1:
            self.nvim.err_write(f"Cannot parse arguments: {' '.join(args)}.")
            return

        self.nvim.command(f"edit {journal_path}/{d}.{extension}")
