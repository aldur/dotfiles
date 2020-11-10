let g:aldur#markdown#header_pattern = '^#\+ .*$'
let g:aldur#markdown#header_start_pattern = '^#\+'

function! aldur#markdown#increase_header_level() abort
    let l:current_level = aldur#markdown#get_current_header_level()
    call setline('.', '#' . (l:current_level == -1 ? ' ' : '') . getline('.'))
endfunction

function! aldur#markdown#decrease_header_level() abort
    let l:current_level = aldur#markdown#get_current_header_level()
    if l:current_level == -1 | return | endif

    let l:new_line = getline('.')[(l:current_level >= 2 ? 1 : 2):]
    call setline('.', l:new_line)
endfunction

" Return the current line's header level (>= 1) or -1
function! aldur#markdown#get_current_header_level() abort
    return matchend(getline('.'), g:aldur#markdown#header_start_pattern)
endfunction

function! aldur#markdown#current_header() abort
    " Move to the current header, if we are not there already.
    if match(getline('.'), g:aldur#markdown#header_pattern) == -1
        call aldur#markdown#previous_header()
    endif
endfunction

function! aldur#markdown#parent_header() abort
    call aldur#markdown#current_header()
    call search('^' . repeat('#', aldur#markdown#get_current_header_level() - 1) . ' .*$', 'bW')
endfunction

function! aldur#markdown#previous_header() abort
    call search(g:aldur#markdown#header_pattern, 'bW')
endfunction

function! aldur#markdown#next_header() abort
    call search(g:aldur#markdown#header_pattern, 'W')
endfunction

" Source: https://gist.github.com/habamax/4662821a1dad716f5c18205489203a67
" TODO: Change this to our your functions.
function! aldur#markdown#header_textobj(inner) abort
    let lnum_start = search('^#\+\s\+[^[:space:]=]', "ncbW")
    if lnum_start
        let lvlheader = matchstr(getline(lnum_start), '^#\+')
        let lnum_end = search('^#\{1,' .. len(lvlheader) .. '}\s', "nW")
        if !lnum_end
            let lnum_end = search('\%$', 'nW')
        else
            let lnum_end -= 1
        endif
        if a:inner && getline(lnum_start + 1) !~ '^#\+\s\+[^[:space:]=]'
            let lnum_start += 1
        endif

        exe lnum_end
        normal! V
        exe lnum_start
    endif
endfunc

function! aldur#markdown#fence_start() abort
    call search('```.\+$', 'bW')
endfunction

function! aldur#markdown#fence_end() abort
    call search('```$', 'W')
endfunction

function! aldur#markdown#visual_move(f) abort
    normal! gv
    call function(a:f)()
endfunction

function! aldur#markdown#tab_imap() abort
    let result = aldur#deoplete#tab_imap()
    if match(getline('.'), '^\s*[*+-]') != -1
                \ && result == deoplete#manual_complete()
        let result = "\<esc>>>A"
    endif

    return result
endfunction

function! aldur#markdown#s_tab_imap() abort
    return "\<esc><<A"
endfunction
