call aldur#wiki#bg_check_has_mermaid()

command! -buffer -range=% -nargs=* WikiExportHTML
            \ call aldur#wiki#export_to_html(<line1>, <line2>, <f-args>)
nnoremap <silent><buffer> <leader>wp :WikiExportHTML<CR>
xnoremap <silent><buffer> <leader>wp :WikiExportHTML<CR>

" Faster rename
nnoremap <silent><buffer> <leader>wr :call aldur#wiki#rename_no_ask()<CR>
" Overwrite default command
command! -buffer WikiPageRename         call aldur#wiki#rename_no_ask()

" This prevents LSP clients from overriding this.
setlocal omnifunc=wiki#complete#omnicomplete

nmap <silent><buffer> gf <plug>(wiki-link-follow)
nmap <silent><buffer> ge <plug>(wiki-link-follow)

" This mapping will recursively search for notes, remove the "Notes" folder
" path and remove the `.md` extension.
" Note that this replaces *i_CTRL-X_CTRL-N*
" Note that this also replaces the mapping from `WikiLinkAdd`,
" because this correctly searches attachments.
" inoremap <silent><buffer> <c-x><c-n> <C-o>:WikiLinkAdd<CR>
lua << EOF
local fzf_default_command = vim.env.FZF_DEFAULT_COMMAND
if fzf_default_command ~= nil and fzf_default_command ~= '' then
    vim.keymap.set({"v", "i"}, "<C-x><C-n>", function()
        local fzf = require('fzf-lua')
        fzf.complete_path({
            cmd = fzf_default_command .. " --search-path " .. vim.g.wiki_root .. "| sed 's#^" .. vim.g.wiki_root .. "/##' | sed 's#.md$##'"
        })
    end, {silent = true, desc = "Fuzzy complete note path", buffer = true})
end
EOF
