function! neoformat#formatters#bib#enabled() abort
    return ['bibtool', ]
endfunction

function! neoformat#formatters#bib#bibtool() abort
    return {
        \ 'exe': 'bibtool',
        \ 'stdin': 1
        \ }
endfunction
