" Set utf-8 as standard encoding
if !has('nvim') " NeoVim defaults to this
    set encoding=utf-8                             " The encoding displayed.
end
set fileencoding=utf-8                             " The encoding written to file.

" End of line (unix EOL is preferred over the dos one and before the mac one).
set fileformats=unix,dos,mac
