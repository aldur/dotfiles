" Inherits from the `beancount` compiler, but runs through pipenv.
runtime! compiler/beancount.vim
if !executable('bean-check')
    finish
endif

let g:current_compiler = 'poetry-beancount'

let s:cpo_save = &cpoptions
set cpoptions-=C

" NOTE: This currently runs a little slowly, because of `pipenv`.
CompilerSet makeprg=cd\ %:h\ &&\ poetry\ run\ bean-check\ %:t

let &cpoptions = s:cpo_save
unlet s:cpo_save
