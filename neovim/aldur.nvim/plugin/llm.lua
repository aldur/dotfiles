local function ollama_model(name)
    return function()
        return require("codecompanion.adapters").extend("ollama", {
            name = name,
            schema = {model = {default = name}, num_predict = {default = -1}}
        })
    end
end

require("codecompanion").setup({
    strategies = {
        chat = {adapter = "qwen2.5-coder:32b"},
        inline = {adapter = "qwen2.5-coder:32b"}
    },
    display = {chat = {show_settings = true}},
    adapters = {
        ["llama3-8k"] = function()
            return require("codecompanion.adapters").extend("ollama", {
                name = "llama3.2-8k",
                schema = {
                    model = {default = "llama3.2:latest"},
                    num_ctx = {default = 8192},
                    num_predict = {default = -1}
                }
            })
        end,
        ["llama3.2"] = ollama_model("llama3.2:latest"),
        ["qwen2.5:32b"] = ollama_model("qwen2.5:32b"),
        ["qwen2.5-coder:32b"] = ollama_model("qwen2.5-coder:32b"),
        ["phi4:14b"] = ollama_model("phi4:14b")
    }
})

-- vim.api.nvim_set_keymap("n", "<C-a>", "<cmd>CodeCompanionActions<cr>",
--                         {noremap = true, silent = true})
-- vim.api.nvim_set_keymap("v", "<C-a>", "<cmd>CodeCompanionActions<cr>",
--                         {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<LocalLeader>a",
                        "<cmd>CodeCompanionChat Toggle<cr>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("v", "<LocalLeader>a",
                        "<cmd>CodeCompanionChat Toggle<cr>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("v", "ga", "<cmd>CodeCompanionChat Add<cr>",
                        {noremap = true, silent = true})

-- Expand 'cc' into 'CodeCompanion' in the command line
vim.cmd([[cab cc CodeCompanion]])
vim.cmd([[cab ccc CodeCompanionChat]])

local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

local progress = require("fidget.progress")
local handle = nil

vim.api.nvim_create_autocmd({"User"}, {
    pattern = "CodeCompanionRequest*",
    group = group,
    callback = function(request)
        if request.match == "CodeCompanionRequestStarted" then
            handle = progress.handle.create({
                title = "CodeCompanion",
                message = "Request started",
                lsp_client = {name = "Ollama"},
                percentage = 0
            })
        else
            if handle then handle:finish() end
        end
    end
})
