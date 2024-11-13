local fzf = require('fzf-lua')
fzf.setup({fzf_colors = true, winopts = {preview = {default = "bat"}}})

vim.keymap.set("n", "<leader><space>", function()
    fzf.files({cwd = vim.fn['aldur#find_root#find_root']()})
end, {noremap = true, silent = true, desc = "FZF files in project."})

vim.keymap.set("n", "<leader>r", function()
    fzf.grep_project({cwd = vim.fn['aldur#find_root#find_root']()})
end, {noremap = true, silent = true, desc = "FZF rg in project."})

local mappings = {
    a = fzf.buffers,
    tt = fzf.btags,
    T = fzf.tags,
    h = fzf.oldfiles,
    [':'] = fzf.command_history,
    u = fzf.grep_cword -- NOTE: LSPs will override this.
}

for key, value in pairs(mappings) do
    vim.keymap.set("n", "<leader>" .. key, value,
                   {noremap = true, silent = true})
end

local fzf_default_command = vim.env.FZF_DEFAULT_COMMAND
if fzf_default_command ~= nil and fzf_default_command ~= '' then
    vim.keymap.set({"n", "v", "i"}, "<C-x><C-f>", function()
        fzf.complete_path({cmd = fzf_default_command})
    end, {silent = true, desc = "Fuzzy complete path"})
end

vim.keymap.set({"n", "v", "i"}, "<C-x><C-k>", function()
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

        }
    })
end, {noremap = true, silent = true})

