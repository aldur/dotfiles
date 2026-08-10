-- nvim-lint linter definition for forge lint
-- Parses Solidity compiler errors, warnings, and lint notes from forge lint
--
-- Two shapes ride the one stderr stream:
--
--  * Lint notes come as rustc-style JSON, one object per line (`--json`).
--    The human rendering changed between forge 1.5 (` --> `) and 1.7
--    (`╭▸`); the JSON shape is the same on both, so the parser reads
--    only the JSON.
--  * Compiler errors stay text on every version, `--json` or not:
--      Error (7576): Undeclared identifier.
--       --> src/ErrorTest.sol:8:9:
--        |
--      8 |         undeclaredVar = 5;
--        |         ^^^^^^^^^^^^^
--
-- A run emits one shape or the other: a failed compile stops the lints,
-- and a clean compile prints no errors.

local severity_map = {
	-- The text compiler diagnostics.
	Error = vim.diagnostic.severity.ERROR,
	Warning = vim.diagnostic.severity.WARN,
	-- The JSON lint diagnostics.
	error = vim.diagnostic.severity.ERROR,
	warning = vim.diagnostic.severity.WARN,
	note = vim.diagnostic.severity.HINT,
	help = vim.diagnostic.severity.HINT,
}

-- `forge lint` reports paths relative to the project root, so compare
-- them on a path boundary. A plain suffix test also accepts a longer
-- name that ends with the same characters: it gives the diagnostics of
-- `src/A.sol` to a buffer for `foosrc/A.sol`.
local function is_current_buffer(bufname, file)
	return bufname == file or bufname:sub(-#file - 1) == "/" .. file
end

-- One JSON line into one diagnostic, or nil: not JSON, not a diagnostic,
-- or a diagnostic for another buffer.
local function json_diagnostic(line, bufname)
	if line:sub(1, 1) ~= "{" then
		return nil
	end
	local ok, d = pcall(vim.json.decode, line)
	if not ok or type(d) ~= "table" or d["$message_type"] ~= "diagnostic" then
		return nil
	end
	local span
	for _, s in ipairs(d.spans or {}) do
		if s.is_primary then
			span = s
			break
		end
	end
	if not span or type(span.file_name) ~= "string" or not is_current_buffer(bufname, span.file_name) then
		return nil
	end
	return {
		-- rustc spans: 1-based columns, end exclusive. nvim: 0-based,
		-- end exclusive, so every field shifts by one.
		lnum = span.line_start - 1,
		col = span.column_start - 1,
		end_lnum = span.line_end - 1,
		end_col = span.column_end - 1,
		severity = severity_map[d.level] or vim.diagnostic.severity.HINT,
		message = d.message,
		code = type(d.code) == "table" and d.code.code or nil,
		source = "forge-lint",
	}
end

local function parse_forge_output(output, bufnr)
	local diagnostics = {}
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local lines = vim.split(output, "\n")

	local i = 1
	while i <= #lines do
		local line = lines[i]

		local json = json_diagnostic(line, bufname)
		if json then
			table.insert(diagnostics, json)
		else
			-- Match error/warning line: "Error (code): message" or "Warning (code): message"
			local severity_str, code, message = line:match("^(Error)%s*%((%d+)%):%s*(.+)$")
			if not severity_str then
				severity_str, code, message = line:match("^(Warning)%s*%((%d+)%):%s*(.+)$")
			end

			if severity_str and code and message then
				-- Look for the file location on the next line
				i = i + 1
				if i <= #lines then
					-- Match: " --> path/to/file.sol:line:col:"
					local file, lnum, col = lines[i]:match("^%s*%-%->%s*(.+):(%d+):(%d+):?$")

					if file and lnum and col and is_current_buffer(bufname, file) then
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
		"--json",
		-- forge >= 1.7 drops info and gas notes unless the severities are
		-- explicit; forge 1.5 emits them by default. The full list keeps
		-- every version at parity.
		"--severity",
		"high",
		"--severity",
		"med",
		"--severity",
		"low",
		"--severity",
		"info",
		"--severity",
		"gas",
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
