#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from deoplete.base.source import Base
from os.path import dirname, relpath, expanduser, isfile
import glob

"""
Deoplete completion for note files.

Original credits: https://vimways.org/2019/personal-notetaking-in-vim/
"""

__author__ = 'Adriano Di Luzio <adrianodl@hotmail.it>'


class Source(Base):
    def __init__(self, vim):
        super().__init__(vim)
        self.name = 'notes'
        self.description = 'Complete note files'
        self.mark = '[N]'
        self.min_pattern_length = 0
        self.rank = 450
        self.filetypes = ['markdown']

        self.wiki_path = expanduser(self.vim.vars['wiki_root'])

    def get_complete_position(self, context):
        if not context['input']:
            return -1

        # Trigger completion if we're currently in the [[link]] syntax
        pos = context['input'].rfind('[[')
        if pos >= 0:
            return pos + 2

        pos = context['input'].rfind('](')
        return pos if pos < 0 else pos + 2

    def gather_candidates(self, context):
        if not context['input']:
            return []

        contents = []
        # Gather all note files and return paths relative to the current
        # note's directory.
        cur_file_dir = dirname(self.vim.buffers[context['bufnr']].name)
        for fname in glob.iglob(self.wiki_path + '**/*', recursive=True):
            if not isfile(fname):
                continue
            fname = relpath(fname, cur_file_dir)
            if fname.endswith('.md'):
                fname = fname[:-3]
            contents.append(fname)
        return contents
