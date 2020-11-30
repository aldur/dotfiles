#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Push text snippets to Things 3 app.
"""

import subprocess
import urllib.parse
import pynvim


__author__ = "Adriano Di Luzio <adrianodl@hotmail.it>"

THINGS_SCHEME = 'things:///'
ADD_ACTION = 'add'
QUICK_ENTRY = 'show-quick-entry'


# Source: `vimr`
def call_open(action, query_params):
    query_params = query_params or {}
    query_params.update({QUICK_ENTRY: True})
    qs = urllib.parse.urlencode(query_params, True, quote_via=urllib.parse.quote)

    url = f"{THINGS_SCHEME}{action}?{qs}"

    subprocess.call(["/usr/bin/open", url])
    return url


@pynvim.plugin
class Things(object):
    def __init__(self, nvim):
        self.nvim = nvim

    @pynvim.command("ToThings3", range=True, nargs="*", sync=True)
    def command_handler(self, args, range):
        start, end = range

        if end - start == 0:
            self.nvim.err_write("No range provided...")
            return -1

        title, *lines = self.nvim.current.buffer[start-1:end]
        kwargs = {'title': title}
        if lines:
            kwargs['notes'] = '\n'.join(lines)

        url = call_open(ADD_ACTION, kwargs)

        self.nvim.err_write(url)
        assert False, url
