" Disable code completion (provided by ALE)
let g:go_code_completion_enabled = 0

" Enable better syntax highlighting
" let g:go_highlight_functions = 1
" let g:go_highlight_function_arguments = 1
" let g:go_highlight_function_calls = 1
" let g:go_highlight_methods = 1
" let g:go_highlight_fields = 1
" let g:go_highlight_structs = 1
" let g:go_highlight_interfaces = 1
" let g:go_highlight_operators = 1
" let g:go_highlight_build_constraints = 1
" let g:go_highlight_extra_types = 1
" let g:go_highlight_variable_declarations = 1
" let g:go_highlight_variable_assignments = 1

" Disable folding
" TODO: A possibly better way to do this is to disable folding at the VIM level.
" let g:go_fold_enable = ['block', 'import', 'varconst', 'package_comment']
" let g:go_fold_enable = []

" Go Format
let g:go_fmt_autosave     = 0  " Don't run :GoFmt on save.
let g:go_imports_autosave = 0  " Don't run :GoImports on save.
let g:go_asmfmt_autosave = 0

" let g:go_fmt_experimental = 0  " On recent VIM version better go fmt should work.
" let g:go_fmt_command    = "goimports"  " Run goimports on save (also calls gofmt)
" let g:go_mod_fmt_autosave = 0

" Do not show info for word under cursor.
let g:go_auto_type_info = 0
let g:go_auto_sameids = 0

let g:go_doc_keywordprg_enabled = 0  " Don't run :GoDoc on K

" Text objects
" let g:go_textobj_include_function_doc = 1
" let g:go_textobj_include_variable     = 1

" Metalinter
let g:go_metalinter_autosave = 0

" Mappings
" autocmd vimrc FileType go nmap <Leader>gi <Plug>(go-imports)
" autocmd vimrc FileType go nmap <leader>r <Plug>(go-run)
" autocmd vimrc FileType go nmap <leader>b <Plug>(go-build)
" autocmd vimrc FileType go nmap <leader>t <Plug>(go-test)
" autocmd vimrc FileType go nmap <leader>c <Plug>(go-coverage)

" autocmd vimrc FileType go nmap <Leader>ds <Plug>(go-def-split)
" autocmd vimrc FileType go nmap <Leader>dv <Plug>(go-def-vertical)
" autocmd vimrc FileType go nmap <Leader>dt <Plug>(go-def-tab)

" autocmd vimrc FileType go nmap <Leader>gd <Plug>(go-doc)
" autocmd vimrc FileType go nmap <Leader>gv <Plug>(go-doc-vertical)

" autocmd vimrc FileType go nmap <Leader>e <Plug>(go-rename)
" autocmd vimrc FileType go nmap <Leader>s <Plug>(go-implements)
