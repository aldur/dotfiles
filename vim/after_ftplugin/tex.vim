setlocal spell conceallevel=0

" Abbreviations {{{ "

iabbrev eg \emph{e.g.}
iabbrev ie \emph{i.e.}
iabbrev etal \emph{et al.}

" }}} Abbreviations "

let b:ale_linters = 'all'

" Try setting the LSP root for the texlab language server
try
    let b:ale_lsp_root = gutentags#get_project_root(expand('%:p:h', 1))
catch
    let b:ale_lsp_root = expand('%:p:h', 1)
endtry

