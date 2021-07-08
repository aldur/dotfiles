function! aldur#ale#fix_gently() abort
    " Preparation: save cursor position
    " (last search is automatically saved because inside a function)
    let l:save = winsaveview()

    " Do the business.
    ALEFix

    " Clean up: restore cursor position.
    call winrestview(l:save)
endfunction


function! aldur#ale#handle_dotenv_linter_format(buffer, lines) abort
    " Inspired by ale/autoload/ale/handlers/cpplint.vim

    " Look for lines like the following.
    " .env:3 UnorderedKey: The DEBUG key should go before the DOMAIN key
    let l:pattern = '^.\{-}:\(\d\+\) *\(.\+\): *\(.\+\)'
    let l:output = []

    for l:match in ale#util#GetMatches(a:lines, l:pattern)
        call add(l:output, {
        \   'lnum': l:match[1] + 0,
        \   'col': 0,
        \   'text': join(split(l:match[3])),
        \   'code': l:match[2],
        \   'type': 'W',
        \})
    endfor

    return l:output
endfunction

function! aldur#ale#go_to_definition_or_tag() abort
    for l:linter in ale#linter#Get(&filetype)
        if !empty(l:linter.lsp)
            ALEGoToDefinition
            return
        endif
    endfor

    tjump
endfunction

" This will show a hover at the caracther _before_
" the closest (to the left) open bracket.
function! aldur#ale#show_hover_at_bracket() abort
    let l:buffer = bufnr('')
    let l:line = getpos('.')[1]
    let l:colum = v:lua.search_before_closest_open_braket_in_line()

    call ale#hover#Show(l:buffer, l:line, l:colum, {'called_from_balloonexpr': 1})
endfunction

