" Place this file in {VIMHOME}/after/ftplugin/python.vim
" Must have syntastic >= 3.5.0-29

" Use Python 3 when the shebang calls for it.
if syntastic#util#parseShebang()['exe'] =~# '\m\<python3'
    let b:syntastic_python_python_exec = 'python3'
    let b:syntastic_python_flake8_exe = 'python3'
    let b:syntastic_python_flake8_args = '-m flake8'
else
    let b:syntastic_python_python_exec = 'python'
endif

nnoremap <F8> :call Preserve("PymodeLintAuto")<cr>
