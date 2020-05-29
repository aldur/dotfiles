function! aldur#markdown#header_decrease() abort
    if match(getline('.'), '^# ') > -1
        let l:search = @/
        execute 'silent! substitute/^# //'
        let @/=l:search
        return
    endif

    execute '.HeaderDecrease'
endfunction

function! aldur#markdown#header_increase() abort
    if match(getline('.'), '^#') > -1
        execute '.HeaderIncrease'
        return
    endif

    let l:search = @/
    execute 'silent! substitute/^/# /'
    let @/=l:search
endfunction

function! aldur#markdown#fence_start() abort
    call search('```.\+$', 'bW')
endfunction

function! aldur#markdown#fence_end() abort
    call search('```$', 'W')
endfunction
