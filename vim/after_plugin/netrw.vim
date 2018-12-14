" Should not be required, but if we don't set it netrw does not have
" network capacities in Neovim
" vint: -ProhibitSetNoCompatible
set nocompatible

" Not an external plugin, but still... :)
let g:netrw_banner = 0  " Disable top banner
let g:netrw_silent = 1  " Do not output `scp` commands etc, while saving.
let g:netrw_browse_split = 4  " Open new files in previous window
let g:netrw_altv = 1  " Split to right
let g:netrw_winsize = 25  " Window height/width on split
let g:netrw_list_hide = netrw_gitignore#Hide()  " Hide git-ignored files

autocmd vimrc FileType netrw setl bufhidden=wipe  " Wipe netrw buffers when hidden
nnoremap - :Vexplore<cr>
