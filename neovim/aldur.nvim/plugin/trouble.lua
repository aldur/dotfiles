require('trouble').setup({
    modes = {
        project_diagnostics = {
            mode = 'diagnostics',
            filter = {
                any = {
                    buf = 0,
                    function(item)
                        return item.filename:find(
                                   vim.fn['aldur#find_root#find_root'](), 1,
                                   true)
                    end
                }
            }
        }
    }
})

-- Pressing `ctrl-t` will load the result in trouble.
local config = require("fzf-lua.config")
local actions = require("trouble.sources.fzf").actions
config.defaults.actions.files["ctrl-t"] = actions.open

vim.keymap.set("n", "<leader>xx", "<cmd>Trouble project_diagnostics toggle<cr>",
               {noremap = true, silent = true})
