require("codecompanion").setup({
    strategies = {chat = {adapter = "ollama"}, inline = {adapter = "ollama"}},
    display = {chat = {show_settings = true}}
})

-- vim.api.nvim_set_keymap("n", "<C-a>", "<cmd>CodeCompanionActions<cr>",
--                         {noremap = true, silent = true})
-- vim.api.nvim_set_keymap("v", "<C-a>", "<cmd>CodeCompanionActions<cr>",
--                         {noremap = true, silent = true})
-- vim.api.nvim_set_keymap("n", "<LocalLeader>a",
--                         "<cmd>CodeCompanionChat Toggle<cr>",
--                         {noremap = true, silent = true})
-- vim.api.nvim_set_keymap("v", "<LocalLeader>a",
--                         "<cmd>CodeCompanionChat Toggle<cr>",
--                         {noremap = true, silent = true})
-- vim.api.nvim_set_keymap("v", "ga", "<cmd>CodeCompanionChat Add<cr>",
--                         {noremap = true, silent = true})

-- Expand 'cc' into 'CodeCompanion' in the command line
vim.cmd([[cab cc CodeCompanion]])

local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})
vim.api.nvim_create_autocmd({"User"}, {
    pattern = "CodeCompanionRequest*",
    group = group,
    callback = function(request)
        if request.match == "CodeCompanionRequestStarted" then
            vim.g.code_companion_processing = true
        elseif request.match == "CodeCompanionRequestFinished" then
            vim.g.code_companion_processing = false
        end
    end
})
