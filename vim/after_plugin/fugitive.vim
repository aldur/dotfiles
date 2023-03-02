if !exists(':Git')
    finish
endif

nnoremap <leader>g :G

cnoreabbrev <expr> Gbrowse (getcmdtype() ==# ':' && getcmdline() ==# 'Gbrowse') ? 'GBrowse' : 'Gbrowse'
