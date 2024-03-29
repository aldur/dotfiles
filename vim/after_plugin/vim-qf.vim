let g:qf_max_height = 8

let g:qf_auto_open_quickfix = 1
let g:qf_auto_open_loclist = 0

" Loclist mappings
nmap <leader>lo <Plug>(qf_loc_toggle)
nmap ]l <Plug>(qf_loc_next)
nmap [l <Plug>(qf_loc_previous)

" Quickfix mappings
nmap <leader>co <Plug>(qf_qf_toggle)
nmap ]q <Plug>(qf_qf_next)
nmap [q <Plug>(qf_qf_previous)
