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
          -- Check if this diagnostic is for the current buffer
          local bufname = vim.api.nvim_buf_get_name(bufnr)
          local is_current_buffer = bufname:match(vim.pesc(file) .. "$") ~= nil

          if is_current_buffer then
            table.insert(diagnostics, {
              lnum = tonumber(lnum) - 1,  -- Convert to 0-indexed
              col = tonumber(col) - 1,    -- Convert to 0-indexed
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

return {
  cmd = "forge",
  stdin = false,
  append_fname = false,
  args = { "lint" },
  stream = "stderr",
  ignore_exitcode = true,
  parser = parse_forge_output,
}
