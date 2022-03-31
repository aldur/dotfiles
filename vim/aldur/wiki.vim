function! aldur#wiki#map_link_create(text) abort
    return a:text
endfunction

" This calls wiki#page#export but sets the output to a custom directory
function! aldur#wiki#export_to_html(line1, line2, ...) abort
    call wiki#paths#pushd(expand(g:wiki_root))
    let l:relative_folder = fnamemodify(expand('%:p'), ':.:h')
    call wiki#paths#popd()

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
        call wiki#page#rename(l:name)
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
    let l:args = [
                \ '--self-contained',
                \ '--lua-filter ' . l:expanded_root . '/assets/header_as_title.lua',
                \ '--lua-filter ' . l:expanded_root . '/assets/todo_to_checkbox.lua',
                \ '-F mermaid-filter',
                \ '--template GitHub.html5',
                \ '--data-dir ' . l:expanded_root . '/assets/'
        \ ]

    return join(l:args, ' ')
endfunction
