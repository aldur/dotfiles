" Insert YAML front matter and header/title
function! aldur#wiki#yaml_frontmatter_and_header() abort
    if exists('g:snips_author')
        let l:author = g:snips_author
    else
        let l:author = 'Adriano Di Luzio'
    end
    execute "normal ggi---\<cr>author: " . l:author . "\<cr>" .
                \ "date: \<C-r>=strftime('%Y-%m-%d %H:%M')\<cr>\<cr>" .
                \ "tags:\<cr>---\<cr>\<cr># " .
                \ expand('%:t:r') ."\<cr>\<esc>"
endfunc

function! aldur#wiki#map_link_create(text) abort
    return a:text
endfunction
