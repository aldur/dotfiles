let g:python_highlight_all = 1  " Enable all Python syntax highlights
compiler python  " Sets  makeprg=python3\ -t\ %

if executable('pipenv')
    setlocal makeprg=cd\ %:h\ &&\ pipenv\ run\ python\ %:t
endif

let b:ale_linters = ['pyls']  " pyls includes pyflakes
let b:ale_fixers = ['black']

" Install python-language-server[all] with pipenv to enable auto-completion
" for each project.
let b:ale_python_auto_pipenv = 1

setlocal formatoptions+=r
