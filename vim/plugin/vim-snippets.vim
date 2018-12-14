" Remap UltiSnips for compatibility with completion handlers
let g:UltiSnipsExpandTrigger                        = '<C-j>'
let g:UltiSnipsJumpForwardTrigger                   = '<C-j>'
let g:UltiSnipsJumpBackwardTrigger                  = '<C-k>'

" Give higher priority to UltiSnips specific snippets over SnipMate ones
let g:UltiSnipsSnippetDirectories=[$HOME . '/.vim/plugged/vim-snippets/UltiSnips']
let g:UltiSnipsEnableSnipMate=1

" Snippets variables
let g:author='Adriano Di Luzio'
let g:snips_author=g:author
let g:email='adrianodl@hotmail.it'
let g:snips_email=g:email
let g:github='https://github.com/aldur'
let g:snips_github=g:github
