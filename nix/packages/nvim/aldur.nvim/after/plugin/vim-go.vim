" Disable code completion (provided by LSP)
let g:go_code_completion_enabled = 0

" Disable folding
" TODO: A possibly better way to do this is to disable folding at the VIM level.
" let g:go_fold_enable = ['block', 'import', 'varconst', 'package_comment']
" let g:go_fold_enable = []

" Go Format
let g:go_fmt_autosave     = 0  " Don't run :GoFmt on save.
let g:go_imports_autosave = 0  " Don't run :GoImports on save.
let g:go_asmfmt_autosave = 0

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
