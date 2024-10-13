local templates_path = vim.fn.expand("<sfile>:p:h:h") .. '/templates'
local templates = {"py", "gnuplot", "tex", "sh"}

local name = "Templates"
pcall(vim.api.nvim_del_augroup_by_name, name)
local group = vim.api.nvim_create_augroup(name, {})
for _, filetype in ipairs(templates) do
    vim.api.nvim_create_autocmd({'BufNewFile'}, {
        group = group,
        pattern = string.format('*.%s', filetype),
        callback = function()
            vim.cmd(string.format([[keepalt 0r %s/skeleton.%s]], templates_path,
                                  filetype))
        end
    })
end
