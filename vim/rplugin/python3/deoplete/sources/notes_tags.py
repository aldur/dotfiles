#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from deoplete.base.source import Base
from os.path import expanduser

import subprocess
from subprocess import PIPE

"""
Deoplete completion for note tags.

Original credits: https://vimways.org/2019/personal-notetaking-in-vim/
"""

__author__ = 'Adriano Di Luzio <adrianodl@hotmail.it>'


class Source(Base):
    def __init__(self, vim):
        super().__init__(vim)
        self.name = 'notes_tags'
        self.description = 'Complete note tags'
        self.mark = '[NT]'
        self.min_pattern_length = 0
        self.rank = 450
        self.filetypes = ['markdown']

        self.wiki_path = expanduser(self.vim.vars['wiki_root'])

    def get_complete_position(self, context):
        if not context['input']:
            return -1

        # Trigger completion if we're currently at a semicolon
        return context['input'].rfind(':')

    def gather_candidates(self, context):
        if not context['input']:
            return []

        try:
            res = subprocess.run(
                ['rg', '--no-filename', '--no-heading', '--no-line-number',
                "\\s*:\\w*:$",
                self.wiki_path], stdout=PIPE, stderr=PIPE
            )
            return [l.strip() for l in res.stdout.decode('utf-8').splitlines()]
        except FileNotFoundError:
            return []
