-- nvim-lint linter definition for forge lint
-- Parses Solidity compiler errors, warnings, and lint notes from forge lint

local severity_map = {
	Error = vim.diagnostic.severity.ERROR,
	Warning = vim.diagnostic.severity.WARN,
	Note = vim.diagnostic.severity.HINT,
}

-- Parse forge lint output
-- Formats:
--   Error (7576): Undeclared identifier.
--    --> src/ErrorTest.sol:8:9:
--     |
--   8 |         undeclaredVar = 5;
--     |         ^^^^^^^^^^^^^
--
--   note[mixed-case-variable]: mutable variables should use mixedCase
--    --> src/MixedCase.sol:5:10
--     |
--   5 |     uint valid_until;
--     |          ^^^^^^^^^^^
local function parse_forge_output(output, bufnr)
	local diagnostics = {}
	local lines = vim.split(output, "\n")

	local i = 1
	while i <= #lines do
		local line = lines[i]

		local severity_str, code, message

		-- Match error/warning line: "Error (code): message" or "Warning (code): message"
		severity_str, code, message = line:match("^(Error)%s*%((%d+)%):%s*(.+)$")
		if not severity_str then
			severity_str, code, message = line:match("^(Warning)%s*%((%d+)%):%s*(.+)$")
		end

		-- Match lint note line: "note[rule-name]: message"
		if not severity_str then
			code, message = line:match("^note%[([^%]]+)%]:%s*(.+)$")
			if code then
				severity_str = "Note"
			end
		end

		if severity_str and code and message then
			-- Look for the file location on the next line
			i = i + 1
			if i <= #lines then
				local location_line = lines[i]
				-- Match: " --> path/to/file.sol:line:col" or "  --> path/to/file.sol:line:col"
				-- Note: lint notes don't have trailing colon
				local file, lnum, col = location_line:match("^%s*%-%->%s*(.+):(%d+):(%d+):?$")

				if file and lnum and col then
					-- `forge lint` reports paths relative to the project root, so compare
					-- them on a path boundary. A plain suffix test also accepts a longer
					-- name that ends with the same characters: it gives the diagnostics of
					-- `src/A.sol` to a buffer for `foosrc/A.sol`.
					local bufname = vim.api.nvim_buf_get_name(bufnr)
					local is_current_buffer = bufname == file or bufname:sub(-#file - 1) == "/" .. file

					if is_current_buffer then
						table.insert(diagnostics, {
							lnum = tonumber(lnum) - 1, -- Convert to 0-indexed
							col = tonumber(col) - 1, -- Convert to 0-indexed
							end_lnum = tonumber(lnum) - 1,
							end_col = tonumber(col),
							severity = severity_map[severity_str] or vim.diagnostic.severity.HINT,
							message = message,
							code = code,
							source = "forge-lint",
						})
					end
				end
			end
		end

		i = i + 1
	end

	return diagnostics
end

-- The project root, from the buffer rather than from nvim's cwd: nvim-lint
-- spawns the linter in the cwd, and a cwd outside the project would make
-- `forge lint` fail in silence.
local function project_root(name)
	return vim.fs.root(name, "foundry.toml")
end

return {
	cmd = "forge",
	stdin = false,
	append_fname = false,
	args = {
		"lint",
		"--root",
		-- nvim-lint evaluates a function argument at spawn time, with the
		-- buffer to lint current.
		function()
			return project_root(vim.api.nvim_buf_get_name(0)) or vim.fn.getcwd()
		end,
	},
	stream = "stderr",
	ignore_exitcode = true,
	parser = parse_forge_output,
	-- LazyVim extension, not nvim-lint: skip the linter when it cannot run.
	-- The editor ships no `forge` (projects bring it through direnv), and
	-- without this gate every lint pass raises "Error running forge: ENOENT".
	condition = function(ctx)
		return vim.fn.executable("forge") == 1 and project_root(ctx.filename) ~= nil
	end,
}
