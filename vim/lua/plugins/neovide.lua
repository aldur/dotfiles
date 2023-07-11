vim.g.neovide_input_use_logo = 1 -- enable use of the logo (cmd) key
vim.keymap.set('v', '<D-c>', '"+y') -- Copy

-- Paste
vim.keymap.set({'n', 'v'}, '<D-v>', '"+gP') -- normal/visual mode
vim.keymap.set('c', '<D-v>', '<C-R>+') -- command mode
vim.keymap.set('i', '<D-v>', function()
    -- If there's a newline character in a registry, `nvim` will put it on a
    -- new line.
    -- This: puts its, removes the additional line, places the curosr at the
    -- end of the put tet.
    if vim.fn.getreg('+'):find("\n") ~= nil then return '<ESC>"+gp`]a' end
    local _, c = unpack(vim.api.nvim_win_get_cursor(0))
    if c == 0 then return '<ESC>"+gPi' end
    return '<ESC>"+gpa'
end, {expr = true}) -- insert mode
vim.keymap.set('t', '<D-v>', '<C-\\><C-O>"+gP') -- terminal mode
