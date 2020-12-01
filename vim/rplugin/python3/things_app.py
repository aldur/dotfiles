#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Push text snippets to Things 3 app.

Inspired by: https://actions.getdrafts.com/a/1CO
"""

import subprocess
import urllib.parse
import pynvim


__author__ = "Adriano Di Luzio <adrianodl@hotmail.it>"

THINGS_SCHEME = 'things'
VIMR_SCHEME = 'vimr'
FILE_SCHEME = 'file'

THINGS_ADD_ACTION = 'add'
THINGS_QUICK_ENTRY = 'show-quick-entry'


def prepare_uri(scheme, action, query_params=None):
    query_params = query_params or {}
    qs = urllib.parse.urlencode(query_params, True, quote_via=urllib.parse.quote)
    return f"{scheme}:///{action}{'?' if qs else ''}{qs}"


# Source: `vimr`
def call_open(action, query_params):
    url = prepare_uri(THINGS_SCHEME, action, query_params)
    subprocess.call(["/usr/bin/open", url])
    return url


@pynvim.plugin
class Things(object):
    def __init__(self, nvim):
        self.nvim = nvim

    @pynvim.command("ToThings3", range=True, nargs="*", sync=True)
    def command_handler(self, args, range):
        buffer_path = self.nvim.current.buffer.name
        start, end = range

        if not end - start:
            title = buffer_path
            notes = []
        else:
            title, *notes = self.nvim.current.buffer[start-1:end]

        file_uri = prepare_uri(FILE_SCHEME, buffer_path)
        notes += ['\n', file_uri]
        noets = '\n'.join(notes).rstrip()
        kwargs = {'title': title, 'notes': notes}
        kwargs.update({THINGS_QUICK_ENTRY: True})

        url = call_open(THINGS_ADD_ACTION, kwargs)
        self.nvim.err_write(url)
