require('aldur.fidget')
require('aldur.code_action') -- Side effects, lightbulb
require('aldur.lsp.diagnostic') -- Side effects, autocmd

local function on_attach_callback(args)
    local bufnr = args.buf
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))

    -- Mappings
    local bufopts = {noremap = true, silent = true, buffer = bufnr}

    -- Call twice to jump into the window.
    vim.keymap.set('n', 'K', function()
        local lnum, cnum = unpack(vim.api.nvim_win_get_cursor(0))
        -- XXX: For some reasons, have to subtract 1 to nvim's line.
        local diagnostics = vim.diagnostic.get(0, {lnum = lnum - 1})

        -- Diagnostic, if any.
        if #diagnostics then
            for _, d in ipairs(diagnostics) do
                if cnum >= d["col"] and cnum < d["end_col"] then
                    -- Found, early exit.
                    return vim.diagnostic.open_float()
                end
            end
        end

        if client.server_capabilities.hoverProvider then
            -- Hover, if available.
            vim.lsp.buf.hover()
        else
            -- Fallback to `investigate` plugin.
            vim.fn['investigate#Investigate']('n')
        end
    end, bufopts)

    if client.server_capabilities.codeActionProvider then
        vim.keymap.set({'n', 'x'}, 'gra', require("fzf-lua").lsp_code_actions,
                       bufopts)
    end

    if client.server_capabilities.documentSymbolProvider then
        vim.keymap.set({'n', 'x'}, 'gO', require("fzf-lua").lsp_document_symbols,
                       bufopts)
    end

    if client.server_capabilities.documentFormattingProvider then
        vim.keymap.set('n', '<leader>f',
                       function() vim.lsp.buf.format({async = true}) end,
                       bufopts)
    end

    vim.keymap.set("n", "<Leader>lo", function()
        vim.diagnostic.setloclist({open = false})
        local window = vim.api.nvim_get_current_win()
        vim.cmd.lwindow()
        vim.api.nvim_set_current_win(window)
    end, {buffer = bufnr})

    if client:supports_method('textDocument/foldingRange') then
        local win = vim.api.nvim_get_current_win()
        vim.wo[win][0].foldexpr = 'v:lua.vim.lsp.foldexpr()'
    end

    if client:supports_method('textDocument/completion') then
        vim.lsp.completion.enable(true, client.id, args.buf,
                                  {autotrigger = true})
    end
end

vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('aldur.lsp', {}),
    callback = on_attach_callback
})

local function on_detach_callback(_)
    -- local client = vim.lsp.get_client_by_id(args.data.client_id)
    -- Do something with the client

    -- TODO: Unset keymaps.
    -- vim.cmd("setlocal tagfunc< omnifunc<")

    -- Here we refresh buffer diagnostic to avoid stale ones
    -- (from the LSP that was detached).
    vim.diagnostic.reset()
    vim.diagnostic.get(0)
end

vim.api.nvim_create_autocmd("LspDetach", {callback = on_detach_callback})

require('aldur.lsp.config') -- Side effects, autocmd

vim.api.nvim_create_user_command('LspTrace', function(_)
    _G.info_message("Enabling LSP tracing...")
    vim.lsp.set_log_level('trace')
    require('vim.lsp.log').set_format_func(vim.inspect)
end, {})
