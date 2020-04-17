let g:python_highlight_all = 1  " Enable all Python syntax highlights
set makeprg=python3\ %

let b:ale_linters = ['pyls']  " pyls includes pyflakes
let b:ale_fixers = ['autopep8']

