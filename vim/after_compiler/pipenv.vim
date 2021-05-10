" Inherits from the `python` compiler, but runs through pipenv.
runtime! compiler/python.vim
if !executable('pipenv')
    finish
endif

let current_compiler = 'pipenv'

let s:cpo_save = &cpoptions
set cpoptions-=C

CompilerSet makeprg=cd\ %:h\ &&\ pipenv\ run\ python\ %:t

let &cpoptions = s:cpo_save
unlet s:cpo_save
