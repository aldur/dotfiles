#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim:ft=python

"""Enable history for pdb sessions."""

import os.path
import readline
import atexit

HISTORY_PATH = os.path.expanduser("~/.pdb_history")


try:
    readline.read_history_file(HISTORY_PATH)
except IOError:
    pass
atexit.register(readline.write_history_file, HISTORY_PATH)
