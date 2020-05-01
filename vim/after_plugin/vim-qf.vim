let g:qf_max_height = 8

" ALE also opens the quickfix
let g:ale_list_window_size = g:qf_max_height
let g:ale_open_list = 0

let g:qf_auto_open_quickfix = 0
let g:qf_auto_open_loclist = 0

" Loclist mappings
nmap <leader>lo <Plug>(qf_loc_toggle)
nmap <leader>ln <Plug>(qf_loc_next)
nmap <leader>lp <Plug>(qf_loc_previous)

" Quickfix mappings
nmap <leader>co <Plug>(qf_qf_toggle)
nmap <leader>cn <Plug>(qf_qf_next)
nmap <leader>cp <Plug>(qf_qf_previous)
