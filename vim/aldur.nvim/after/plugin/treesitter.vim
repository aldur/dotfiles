lua require('plugins/treesitter')

" This tries to fix an issue where UltiSnips would not load the correct
" snippets, e.g. reporting `markdown_inline` for Markdown and, as a
" result, not listing Markdown snippets.
" FIXME: This might not work if this doesn't get called with every buffer.
py3 from UltiSnips import vim_helper; vim_helper.buf = vim_helper.VimBuffer()
