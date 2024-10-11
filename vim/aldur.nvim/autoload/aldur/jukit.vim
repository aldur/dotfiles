function aldur#jukit#jukit() abort
    " https://github.com/luk400/vim-jukit

    echomsg "Activating Jukit plugin..."
    call plug#load('vim-jukit')

    let l:root = aldur#find_root#find_root()

    let g:jukit_shell_cmd = luaeval("require('plugins/python').executable_path('" . root . "', 'ipython3')")
    echomsg "Setting iPython3 path to " . g:jukit_shell_cmd

    " This works, but it's not perfect.
    " Mappings are buffer-local, but all else is global.

    nnoremap <buffer> <leader>cc :call jukit#send#until_current_section()<cr>
    nnoremap <buffer> c<cr> :call jukit#send#section(0)<cr>
    vnoremap <buffer> <cr> :<C-U>call jukit#send#selection()<cr>

    " nnoremap <buffer> m<cr> :call jukit#send#all()<cr>

    " code cell
    nnoremap <buffer> <leader>co :call jukit#cells#create_below(0)<cr>
    nnoremap <buffer> <leader>cO :call jukit#cells#create_above(0)<cr>
    " text cell
    nnoremap <buffer> <leader>ct :call jukit#cells#create_below(1)<cr>
    nnoremap <buffer> <leader>cT :call jukit#cells#create_above(1)<cr>

    nnoremap <buffer><leader>np :call jukit#convert#notebook_convert("jupyter-notebook")<cr>

    call jukit#splits#output()

    edit
endfunction
