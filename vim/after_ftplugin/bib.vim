if executable('bibtool')
    function! Bibtool(buffer) abort
        return { 'command': 'bibtool %t' }
    endf
    let b:ale_fixers = ['Bibtool']
endif
