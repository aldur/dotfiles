# encoding: utf-8
# vim:ft=python

import os.path
import readline
import atexit

history_path = os.path.expanduser("~/.pdb_history")

if os.path.exists(history_path):
    readline.read_history_file(history_path)
write_history = lambda: readline.write_history_file(history_path)
atexit.register(write_history)
