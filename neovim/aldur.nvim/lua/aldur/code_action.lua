local M = {}

-- Remove annoying highlight and lightbulb, just color the line.
vim.fn.sign_define('LightBulbSign', {
    text = "",
    texthl = "",
    linehl = "",
    numhl = "DiagnosticOk"
})

local LB_SIGN_GROUP = "nvim-lightbulb"
local LB_SIGN_NAME = "LightBulbSign"
local LB_SIGN_PRIORITY = 25
M.LB_CLIENTS_TO_IGNORE = {'pylsp'}

function M._update_sign(priority, old_line, new_line, bufnr)
    bufnr = bufnr or "%"

    if old_line then
        vim.fn.sign_unplace(LB_SIGN_GROUP, {id = old_line, buffer = bufnr})

        -- Update current lightbulb line
        vim.b.lightbulb_line = nil -- luacheck: ignore 122
    end

    -- Avoid redrawing lightbulb if code action line did not change
    if new_line and (vim.b.lightbulb_line ~= new_line) then
        vim.fn.sign_place(new_line, LB_SIGN_GROUP, LB_SIGN_NAME, bufnr,
                          {lnum = new_line, priority = priority})
        -- Update current lightbulb line
        vim.b.lightbulb_line = new_line -- luacheck: ignore 122
    end
end

-- Taken from https://github.com/neovim/nvim-lspconfig/wiki/Code-Actions
function M.code_action_listener()
    local method = "textDocument/codeAction"
    -- Check for code action capability
    local code_action_cap_found = false
    for _, client in pairs(vim.lsp.get_clients({bufnr = 0, method = method})) do
        if not vim.tbl_contains(M.LB_CLIENTS_TO_IGNORE, client.name) then
            code_action_cap_found = true
            break
        end
    end

    if not code_action_cap_found then return end
    local params = vim.lsp.util.make_range_params()

    local line = params.range.start.line

    local context = {diagnostics = vim.diagnostic.get(0, {lnum = line})}
    params.context = context

    vim.lsp.buf_request_all(0, method, params, function(responses)
        local has_actions = false
        for client_id, resp in pairs(responses) do
            if resp.result and
                not vim.tbl_contains(M.LB_CLIENTS_TO_IGNORE, client_id) and
                not vim.tbl_isempty(resp.result) then
                has_actions = true
                break
            end
        end

        if has_actions then
            M._update_sign(LB_SIGN_PRIORITY, vim.b.lightbulb_line, line + 1)
        else
            M._update_sign(LB_SIGN_PRIORITY, vim.b.lightbulb_line, nil)
        end
    end)
end

function M.code_action_autocmd()
    local name = "LightBulb"
    pcall(vim.api.nvim_del_augroup_by_name, name)
    local id = vim.api.nvim_create_augroup(name, {})
    vim.api.nvim_create_autocmd({"CursorHold", "CursorHoldI"}, {
        pattern = {"*"},
        group = id,
        callback = M.code_action_listener
    })
end

M.code_action_autocmd() -- This creates the autocmd to trigger the lightbulb

return M
