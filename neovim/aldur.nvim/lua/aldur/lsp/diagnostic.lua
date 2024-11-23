local M = {}

function M.diagnostic_autocmd()
    local name = "QFDiagnostic"
    pcall(vim.api.nvim_del_augroup_by_name, name)
    local group = vim.api.nvim_create_augroup(name, {})

    vim.api.nvim_create_autocmd({'DiagnosticChanged'}, {
        group = group,
        callback = function(args)
            if (args and args.data) then vim.fn["lightline#update"]() end
        end
    })
end
--
-- NOTE: This creates the autocmd to populate / update the QF with the diagnostics
M.diagnostic_autocmd()

local default_buffer_config = {
    -- variable, default value, command (+Toggle)
    {'signs', true, 'Signs'}, --
    {'virtual_text', false, 'VirtualText'}, --
    {'update_in_insert', false, 'UpdateInInsert'}, --
    {'underline', true, "Underline"}, --
    {'inlay_hint', true, "InlayHint"}
}

M.buffer_config_getters = {}

for _, config_detail in ipairs(default_buffer_config) do
    local name = config_detail[1]
    local default_value = config_detail[2]
    local command = config_detail[3]

    local buffer_option = 'diagnostic_' .. name .. '_enabled'

    local get_buffer_option = function(_, bufnr)
        local v
        if bufnr ~= nil then
            v = vim.b[bufnr][buffer_option]
        else
            v = vim.b[buffer_option]
        end
        if v == nil then return default_value end
        return v
    end

    M[buffer_option] = get_buffer_option
    M.buffer_config_getters[name] = get_buffer_option

    local toggle = function(_)
        local action = "Enabling"
        local current = get_buffer_option()
        if current then action = "Disabling" end
        _G.info_message(action .. " " .. command .. "...")
        vim.b[buffer_option] = not current
        M.reload_config()
    end

    vim.api.nvim_create_user_command("Toggle" .. command, toggle, {bang = true})
end

vim.api.nvim_create_user_command("ToggleAllDiagnostics", function(_)
    local opts = {nsid = nil, bufnr = 0}
    vim.diagnostic.enable(not vim.diagnostic.is_enabled(opts), opts)
end, {bang = true})

function M.reload_config()
    vim.diagnostic.config({
        virtual_text = function(_, bufnr)
            if M.buffer_config_getters.virtual_text(_, bufnr) then
                return {prefix = '●', source = "if_many"}
            end
            ---@diagnostic disable-next-line: return-type-mismatch
            return false
        end,

        signs = M.buffer_config_getters.signs,
        underline = M.buffer_config_getters.underline,

        -- delay update diagnostics
        update_in_insert = M.buffer_config_getters.update_in_insert,

        severity_sort = true
    })

    local inlay_hint = M.buffer_config_getters.inlay_hint()
    vim.lsp.inlay_hint.enable(inlay_hint)
end

function M.configure_highlights()
    for _, value in ipairs({
        "DiagnosticUnderlineHint", "DiagnosticUnderlineWarn",
        "DiagnosticUnderlineError"
    }) do
        local hl = vim.api.nvim_get_hl(0, {name = value, create = false})

        local new_hl = vim.deepcopy(hl)

        new_hl.underline = true
        new_hl.undercurl = nil

        new_hl.cterm.underline = true
        new_hl.cterm.undercurl = nil

        ---@diagnostic disable-next-line: param-type-mismatch
        vim.api.nvim_set_hl(0, value, new_hl)
    end
end

M.configure_highlights()

M.reload_config() -- First time initialization.
