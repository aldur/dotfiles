vim.g.neovide_input_use_logo = 1 -- enable use of the logo (cmd) key

-- https://github.com/neovide/neovide/issues/2680#issuecomment-2204900647
if vim.fn.has("macos") then
    vim.keymap.set('v', '<D-c>', '"+y') -- Copy
    vim.keymap.set({'n', 'v', 's', 'x', 'o', 'i', 'l', 'c', 't'}, '<D-v>',
                   function()
        vim.api.nvim_paste(vim.fn.getreg('+'), true, -1)
    end, {noremap = true, silent = true})
else
    vim.keymap.set('v', '<C-S-c>', '"+y') -- Copy
    vim.keymap.set({'n', 'v', 's', 'x', 'o', 'i', 'l', 'c', 't'}, '<C-S-v>',
                   function()
        vim.api.nvim_paste(vim.fn.getreg('+'), true, -1)
    end, {noremap = true, silent = true})
end
