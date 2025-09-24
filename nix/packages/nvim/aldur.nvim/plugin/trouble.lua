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

vim.keymap.set("n", "<leader>xx",
               "<cmd>Trouble project_diagnostics toggle filter.buf=0<cr>",
               {noremap = true, silent = true})

vim.keymap.set("n", "<leader>xX", "<cmd>Trouble project_diagnostics toggle<cr>",
               {noremap = true, silent = true})

