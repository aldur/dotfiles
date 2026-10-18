local M = {}

-- link.vim supplies one-based byte positions. Keep its legacy syntax fallback
-- for buffers without a parser, while recognizing Markdown's injected spans.
function M.is_code(lnum, col)
	local ok, node = pcall(function()
		local parser = vim.treesitter.get_parser(0)
		if not parser then
			return nil
		end
		parser:parse({ lnum - 1, lnum })
		return vim.treesitter.get_node({ pos = { lnum - 1, col - 1 }, ignore_injections = false })
	end)
	while ok and node do
		if node:type() == "code_span" then
			return true
		end
		node = node:parent()
	end
	return false
end

return M
