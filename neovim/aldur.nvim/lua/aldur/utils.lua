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

-- If current Lua buffer has been `require`d, reload it.
-- See `:h lua-module-load` for more.
function M.reload_module()
    local filetype = vim.bo.filetype -- Get the current file's filetype
    if filetype ~= "lua" then
        error("Current file is not a Lua file.")
        return
    end

    local current_file = vim.fn.expand("%:p") -- Get the full path of the current file

    -- HACK
    -- We know from `:h require()` that modules get pushed to `package.loaded`.
    -- A modukle stored at lua/foo/bar.lua will be stored with key `foo.bar`.
    -- Anything _before_ `lua` must be part of `runtimepath`
    -- NOTE that:
    -- Nvim searches for |:runtime| files in:
    -- 1. all paths in 'runtimepath'
    -- 2. all "pack/*/start/*" dirs
    -- See `:h runtime-search-path`.
    --
    -- So what do we do? Well, we hack it.
    -- Find the latest occurrence of `/lua/*.lua` in our file.
    -- Assume that's our module.
    -- Try to force reload it.
    --
    -- Incidentally, this works also to replace modules loaded from `nix` store
    -- with a corresponding module loaded from `~/.dotfiles`

    -- NOTE: We need to reverse to make sure we find the latest occurrence.
    local module_runtimepath, maybe_module = current_file:match("(.*)/lua/(.*)%.lua")

    if maybe_module == nil then
        error("Current file is not on Lua's module path (searched '" ..
                  maybe_module .. "').")
        return
    end

    -- NOTE: We drop `/init.lua` suffix since it you can just load its
    -- containing module: `require("foo/bar")` instead of
    -- `require("foo/bar/init")`
    maybe_module = maybe_module:gsub("/init$", ""):gsub("/", ".")

    if package.loaded[maybe_module] == nil then
        error("Guessed module '" .. maybe_module .. "' was not on loaded.")
        return
    end

    local old_runtimepath = vim.opt.runtimepath
    vim.opt.runtimepath:prepend{module_runtimepath}

    package.loaded[maybe_module] = nil
    require(maybe_module)

    vim.opt.runtimepath = old_runtimepath

    vim.notify(string.format("Reloading module '%s'.", maybe_module),
               vim.log.levels.INFO)
end

return M
