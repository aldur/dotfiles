let g:aldur#markdown#header_pattern = '^#\+ .*$'

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

" Return the header level at given line (>= 1) or -1
function! aldur#markdown#get_header_level(lnum) abort
    let header_start_pattern = '^#\+'
    return matchend(getline(a:lnum), header_start_pattern)
endfunction

" Return the current line's header level (>= 1) or -1
function! aldur#markdown#get_current_header_level() abort
    return aldur#markdown#get_header_level('.')
endfunction

function! aldur#markdown#to_current_header() abort
    " Move to the current header, if we are not there already.
    if match(getline('.'), g:aldur#markdown#header_pattern) == -1
        call aldur#markdown#to_previous_header()
    endif
endfunction

function! aldur#markdown#to_parent_header() abort
    call aldur#markdown#to_current_header()
    call search('^' . repeat('#', aldur#markdown#get_current_header_level() - 1) . ' .*$', 'bW')
endfunction

function! aldur#markdown#to_previous_header() abort
    call search(g:aldur#markdown#header_pattern, 'bW')
endfunction

function! aldur#markdown#to_next_header() abort
    call search(g:aldur#markdown#header_pattern, 'W')
endfunction

" Source: https://gist.github.com/habamax/4662821a1dad716f5c18205489203a67
function! aldur#markdown#header_textobj(inner) abort
    let header_line = search(g:aldur#markdown#header_pattern, 'ncbW')
    if header_line
        let header_level = aldur#markdown#get_header_level(header_line)
        let block_end = search('^#\{1,' . header_level . '}\s', 'nW')
        if !block_end
            let block_end = search('\%$', 'nW')
        else
            let block_end -= 1
        endif
        if a:inner && getline(header_line + 1) !~ g:aldur#markdown#header_pattern
            let header_line += 1
        endif

        execute block_end
        normal! V
        execute header_line
    endif
endfunc

function! aldur#markdown#to_fence_start() abort
    call search('```.\+$', 'bW')
endfunction

function! aldur#markdown#to_fence_end() abort
    call search('```$', 'W')
endfunction

function! aldur#markdown#fence_textobj(inner) abort
    let start_line = search('```.\+$', 'ncbW')
    if !start_line
        return
    endif

    let end_line = search('```$', 'nW')
    if !end_line
        return
    endif

    if a:inner
        let start_line = start_line + 1
        let end_line = end_line - 1
    endif

    execute end_line
    normal! V
    execute start_line
endfunc

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

" De-indent the current line. Disables `indentexpr` to prevent conflicts.
function! aldur#markdown#s_tab_imap() abort
    let l:indent_expr = &indentexpr
    let &indentexpr = ''

    execute 'normal! <<'
    startinsert!

    let &indentexpr = l:indent_expr
endfunction
