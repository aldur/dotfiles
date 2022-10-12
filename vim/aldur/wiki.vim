" This calls wiki#page#export but sets the output to a custom directory
function! aldur#wiki#export_to_html(line1, line2, ...) abort
    call wiki#paths#pushd(expand(g:wiki_root))
    let l:relative_folder = fnamemodify(expand('%:p'), ':.:h')
    call wiki#paths#popd()

    if exists('s:args') == 0
        " aldur#wiki#export_args sets s:args
        " Because `export_args` does `system` calls, it is slow.
        " This ensures it only does that once.
        let g:wiki_export = {
                    \ 'args' : aldur#wiki#export_args(),
                    \ 'from_format' : 'markdown',
                    \ 'ext' : 'html',
                    \ 'link_ext_replace': v:false,
                    \ 'view' : v:true,
                    \ 'output': fnamemodify(tempname(), ':h'),
                    \}
    endif

    call wiki#page#export(
                \ a:line1, a:line2,
                \ '-output', expand(g:wiki_root . '/../HTML/' . l:relative_folder)
                \ )
endfunction

function! aldur#wiki#rename_no_ask() abort
    redraw!
    echo 'Enter new name (without extension):'
    let l:name = input('> ', expand('%:p:t:r'))
    if l:name !=# ''
        call wiki#page#rename({'new_name': l:name})
    endif
endfunction

function! aldur#wiki#template(context) abort
    if exists('g:snips_author')
        let l:author = g:snips_author
    else
        let l:author = 'Adriano Di Luzio'
    end

    call append(0, '---')
    call append(1, 'author: ' . l:author)
    call append(2, 'date: ' . a:context.date . ' ' . a:context.time)
    call append(3, 'tags:')
    call append(4, '---')
    call append(5, '')
    call append(6, '# ' . a:context.name)
endfunction

function! aldur#wiki#export_args() abort
    let l:expanded_root = expand(g:wiki_root)
    let s:args = [
                \ '--embed-resources',
                \ '--standalone',
                \ '--lua-filter ' . l:expanded_root . '/assets/header_as_title.lua',
                \ '--lua-filter ' . l:expanded_root . '/assets/todo_to_checkbox.lua',
                \ '--template GitHub.html5',
                \ '--data-dir ' . l:expanded_root . '/assets/'
        \ ]

    if get(s:, 'has_mermaid', 0)
        " Set by `aldur#wiki#bg_check_has_mermaid`, must be called before this.
        call add(s:args, '-F mermaid-filter')
    endif

    return join(s:args, ' ')
endfunction

function! aldur#wiki#bg_check_has_mermaid() abort
    let l:callbacks = {
                \ 'on_exit': function('aldur#wiki#on_mermaid_job_exit')
                \ }
    call jobstart('npm list -g --depth 0 | grep mermaid-filter', l:callbacks)
endfunction

function! aldur#wiki#on_mermaid_job_exit(job_id, exit_code, _) abort
    let s:has_mermaid = 0
    if a:exit_code == 0
        let s:has_mermaid = 1
    endif
endfunction
