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

" This calls wiki#page#export but sets the output to a custom directory
function! aldur#wiki#export_to_html(line1, line2, ...) abort
    call wiki#paths#pushd(expand(g:wiki_root))
    let l:relative_folder = fnamemodify(expand('%:p'), ':.:h')
    call wiki#paths#popd()

    call wiki#page#export(
                \ a:line1, a:line2,
                \ '-output', expand('../HTML/' . l:relative_folder)
                \ )
endfunction
