local fzf = require('fzf-lua')
local actions = require("fzf-lua.actions")
local defaults = require('fzf-lua.defaults').defaults

fzf.setup({
    "hide",
    fzf_colors = true,
    winopts = {
        -- Make it full-width on smaller windows.
        -- XXX This needs a function, but unclear how to make that work after deprecation.
        -- width = vim.o.columns > 100 and 0.80 or 1,
        preview = {default = "bat"}
    },
    keymap = {
        builtin = {
            true,
            ["<M-p>"] = "toggle-preview",
            ["<M-S-p>"] = "toggle-preview-cw"
        },
        fzf = {true, ["alt-p"] = "toggle-preview"}
    },
    lsp = {code_actions = {previewer = "codeaction_native"}}
})

fzf.setup_fzfvim_cmds()

vim.keymap.set("n", "<leader><space>", function()
    fzf.files({cwd = vim.fn['aldur#find_root#find_root']()})
end, {noremap = true, silent = true, desc = "FZF files in project."})

local grep_options = function()
    return {
        cwd = vim.fn['aldur#find_root#find_root'](),
        actions = vim.tbl_extend('keep', {
            -- NOTE: ctrl-i conflicts with `<tab>` and will prevent you from toggling items
            ["ctrl-l"] = {actions.toggle_ignore},
            ["ctrl-h"] = {actions.toggle_hidden}
        }, defaults.grep.actions),
        rg_opts = "--hidden " .. defaults.grep.rg_opts,
        resume = true
    }
end

vim.keymap.set("n", "<leader>r",
               function() fzf.grep_project(grep_options()) end,
               {noremap = true, silent = true, desc = "FZF rg in project."})

local mappings = {
    bb = fzf.buffers,
    tt = fzf.btags,
    T = function()
        -- Make th displayed tag path relative to the project root.
        local cwd = vim.fn['aldur#find_root#find_root']()

        local tags = vim.fn.expand(vim.fn.tagfiles()[1])
        if not tags:match("^/") then
            tags = vim.fn.getcwd() .. "/" .. tags
        end

        fzf.tags({cwd = cwd, ctags_file = tags})
    end,
    -- T = fzf.tags,
    h = fzf.oldfiles,
    [':'] = fzf.command_history,
    u = function() fzf.grep_cword(grep_options()) end -- NOTE: LSPs will override this.
}

for key, value in pairs(mappings) do
    vim.keymap.set("n", "<leader>" .. key, value,
                   {noremap = true, silent = true})
end

local fzf_default_command = vim.env.FZF_DEFAULT_COMMAND
if fzf_default_command ~= nil and fzf_default_command ~= '' then
    vim.keymap.set({"v", "i"}, "<C-x><C-f>", function()
        fzf.complete_path({cmd = fzf_default_command})
    end, {silent = true, desc = "Fuzzy complete path"})
end

vim.keymap.set({"v", "i"}, "<C-x><C-k>", function()
    local dictionary = vim.o.dictionary
    if dictionary == "" or dictionary == nil then
        dictionary = "/usr/share/dict/words"
    end

    fzf.fzf_exec("cat " .. dictionary, {complete = true})
end, {silent = true, desc = "Fuzzy complete words"})

vim.keymap.set("n", "<leader>n", function()
    local wiki_root = vim.fn.expand(vim.g.wiki_root)
    fzf.grep({
        search = "",
        cwd = wiki_root,
        actions = {
            ['ctrl-x'] = function()
                vim.cmd("edit " .. wiki_root .. '/' .. fzf.get_last_query() ..
                            ".md")
            end

        },
        files = {git_icons = false, file_icons = false}
    })
end, {noremap = true, silent = true})

-- NOTE: Currently this displays snippets but doesn't do anything else.
vim.api.nvim_create_user_command("Snippets", function()
    local snippets = require('snippets').get_loaded_snippets()
    local to_show = {}

    for _, v in pairs(snippets) do
        to_show[#to_show + 1] =
            v['prefix'] .. ": " .. v['description'] " -> " ..
                vim.inspect(v['body'])
    end

    fzf.fzf_exec(to_show)
end, {})

vim.api.nvim_create_user_command("GBranches", function() fzf.git_branches() end,
                                 {})

-- Pressing `ctrl-t` will load the result in trouble.
local config = require("fzf-lua.config")
local trouble_actions = require("trouble.sources.fzf").actions
config.defaults.actions.files["ctrl-t"] = trouble_actions.open
