setlocal spell textwidth=72

" Autocomplete also ` and ```
" https://github.com/tmsvg/pear-tree/blob/
" 3bb209d9637d6bd7506040b2fcd158c9a7917db3/after/ftplugin/markdown.vim#L22
let b:pear_tree_pairs = extend(deepcopy(g:pear_tree_pairs), {
            \ '`': {'closer': '`'},
            \ '```': {'closer': '```'}
            \ }, 'keep')
