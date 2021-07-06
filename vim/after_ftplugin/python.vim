let g:python_highlight_all = 1  " Enable all Python syntax highlights

" compiler python  " Sets makeprg=python3\ -t\ %
compiler pipenv  " Calls `compiler python` and sets makeprg=cd\ %:h\ &&\ pipenv\ run\ python\ %:t

let b:ale_linters = ['pyls']
let b:ale_fixers = ['black']

" To configure pyright, we need to point it to a pipenv virtualenv.
" We do this asynchronously so that we don't block while opening the file.
let s:venv_path = []
function! s:OnEvent(job_id, data, event) dict
    if a:event ==# 'stdout'
        let s:venv_path += a:data
    elseif a:event ==# 'exit'
        " Finished!
        let l:pipenv_status = a:data
        if l:pipenv_status == 0
            let b:ale_python_pyright_config = {
                        \ 'python': {
                            \   'venvPath': join(s:venv_path, ''),
                            \   'analysis': {'extraPaths': expand('%:p:h')},
                            \ },
                        \ }
        endif
    endif
endfunction

let s:opts = {
            \ 'on_stdout': function('s:OnEvent'),
            \ 'on_exit': function('s:OnEvent'),
            \ 'cwd': aldur#find_root#find_root()
            \ }

let s:job = jobstart('pipenv --venv', s:opts)
" let b:ale_linters += ['pyright']

" Install python-language-server[all] with pipenv to enable auto-completion
" for each project.
let b:ale_python_auto_pipenv = 1

setlocal formatoptions+=r
