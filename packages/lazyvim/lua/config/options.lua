-- Disable automatic yanking to clipboard
vim.opt.clipboard = ""

-- Disable animations
vim.g.snacks_animate = false

-- We use `basedpyright`
vim.g.lazyvim_python_lsp = "basedpyright"

-- Fuzzy completion
-- vim.opt.completeopt:append { 'fuzzy' }

-- No inline diagnostics in prose: harper and markdownlint get chatty while a
-- sentence is still being typed. Wrapping the handler (rather than
-- vim.diagnostic.config, which is global) keeps signs, underlines and the
-- pickers; only the virtual text goes, and only for markdown buffers.
local virtual_text = vim.diagnostic.handlers.virtual_text
vim.diagnostic.handlers.virtual_text = {
	show = function(namespace, bufnr, diagnostics, opts)
		if vim.bo[bufnr].filetype:match("^markdown") then
			return
		end
		virtual_text.show(namespace, bufnr, diagnostics, opts)
	end,
	hide = virtual_text.hide,
}
