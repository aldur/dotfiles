require('aldur.fidget')
require('aldur.code_action') -- Side effects, autocmd

require('aldur.lsp.diagnostic') -- Side effects, autocmd

local function on_attach_callback(args)
    local bufnr = args.buf

    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client == nil then return end

    require("lsp_signature").on_attach({
        -- This is mandatory, otherwise border config won't get registered.
        bind = true,
        handler_opts = {border = "single"},
        bufnr
    })

    -- Mappings
    local bufopts = {noremap = true, silent = true, buffer = bufnr}

    if client.server_capabilities.referencesProvider then
        -- Mnemonic for Usages
        vim.keymap.set('n', '<leader>u', vim.lsp.buf.references, bufopts)
    end

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
        vim.keymap.set({'n', 'x'}, 'gK',
                       require("actions-preview").code_actions, bufopts)
    end

    if client.server_capabilities.documentFormattingProvider then
        vim.keymap.set('n', '<leader>f',
                       function() vim.lsp.buf.format({async = true}) end,
                       bufopts)
    end

    -- Our LSP configuration places diagnostic in the loclist.
    -- This overrides the default commands to go to prev/next element in the
    -- loclist. It has the advantage to take the cursor position into consideration.
    local diagnostic_goto_opts = {float = false}
    vim.keymap.set('n', '[l', function()
        vim.diagnostic.goto_prev(diagnostic_goto_opts)
    end, bufopts)
    vim.keymap.set('n', ']l', function()
        vim.diagnostic.goto_next(diagnostic_goto_opts)
    end, bufopts)
end

vim.api.nvim_create_autocmd('LspAttach', {callback = on_attach_callback})

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
