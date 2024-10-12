local M = {}

M._nerdfont = nil

function M.is_nerdfont()
    if M._nerdfont ~= nil then return M._nerdfont end

    -- If there's a Nerd Font set, display fancy icons.
    local guifont = vim.opt.guifont:get()
    M._nerdfont = #guifont == 1 and guifont[1]:lower():find('nerd', 0, true) ~=
                      nil
    return M._nerdfont
end

function M.buffer_options_default(bufnr, name, default)
    local ok, result = pcall(vim.api.nvim_buf_get_var, bufnr, name)
    -- If not set, rely on the default value.
    if not ok then return default end
    return result
end

function M.configure_signs()
    -- _G.info_message("Configuring signs...")
    local highlights = {Error = "Title", Hint = "MoreMsg", Info = "ModeMsg"}

    for type, hl in pairs(highlights) do
        -- https://github.com/neovim/nvim-lspconfig/wiki/
        -- UI-Customization#change-diagnostic-symbols-in-the-sign-column-gutter
        local sign = "DiagnosticSign" .. type
        if vim.fn.sign_define(sign, {numhl = hl, text = ""}) ~= 0 then
            _G.warning_message("Couldn't set sign " .. type)
        end
    end

    -- "Warn" -> "WarningMsg"
    -- Special treatment
    if vim.fn.sign_define("DiagnosticSignWarn",
                          {numhl = "WarningMsg", text = ""}) ~= 0 then
        _G.warning_message("Couldn't set sign " .. type)
    end
end

-- If current Lua buffer is in `runtimepath`, reload it.
function M.reload_package()
    local filetype = vim.bo.filetype -- Get the current file's filetype
    if filetype ~= "lua" then
        error("Current file is not a Lua file.")
        return
    end

    local current_file = vim.fn.expand("%:p") -- Get the full path of the current file

    -- HACK
    -- Most of the time, I'll be editing in my `~/.dotfiles` folder.
    current_file = current_file:gsub("%.dotfiles/vim", ".vim")

    local runtimepath = vim.o.runtimepath -- Get the runtimepath as a string

    -- Split the runtimepath into a table of paths
    local paths = vim.split(runtimepath, ",")

    -- Check if the current file's expanded path starts with any of the expanded runtimepath paths
    for _, path in ipairs(paths) do
        local expanded_path = vim.fn.expand(path)
        expanded_path = vim.loop.fs_realpath(expanded_path)

        local prefix = expanded_path

        if prefix ~= nil and current_file:match("^" .. prefix) then
            local stripped_path =
                current_file:gsub("^" .. prefix .. "/lua/", ""):gsub(".lua$", "")

            vim.notify(string.format("Reloading package '%s'.", stripped_path),
                       vim.log.levels.INFO)
            package.loaded[stripped_path] = nil
            require(stripped_path)

            -- NOTE: We stop at the first match.
            return
        end
    end

    error("Current file is not in runtimepath.")
end

return M
