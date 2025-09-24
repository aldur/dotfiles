" Inherits from the `cargo` compiler, but runs through pipenv.
runtime! compiler/cargo.vim

let g:current_compiler = 'cargo_direnv'

let s:cpo_save = &cpoptions
set cpoptions-=C

" NOTE: There would be `cargo -C` but is in nighly only
let s:prefix = 'CompilerSet makeprg=pushd\ %:p:h\ &&\ direnv\ exec\ %:p:h\ cargo\ '
let s:suffix = '\ $*'

if exists('g:cargo_makeprg_params')
    let s:suffix = escape(g:cargo_makeprg_params, ' \|"')
endif

execute s:prefix.s:suffix

let &cpoptions = s:cpo_save
unlet s:cpo_save
