-- Compiler definition for Foundry's forge lint command
-- This allows parsing forge lint errors and warnings in the quickfix window
--
-- Usage:
--   :compiler forge-lint
--   :make
--
-- Or use with LazyVim's keybindings for linting

vim.bo.makeprg = "forge lint"

-- Error format for forge lint output
--
-- Forge lint produces output identical to forge build:
--   Error (7576): Undeclared identifier.
--    --> src/ErrorTest.sol:8:9:
--     |
--   8 |         undeclaredVar = 5;
--     |         ^^^^^^^^^^^^^
--
--   Warning (5667): Unused function parameter.
--    --> src/LintTest.sol:16:32:
--     |
--  16 |     function unused(uint256 x, uint256 y) public pure returns (uint256) {
--     |                                ^^^^^^^^^

vim.bo.errorformat = table.concat({
  -- Match error/warning header with code and message
  "%EError (%n): %m",
  "%WWarning (%n): %m",

  -- Match file location: " --> path/to/file.sol:line:column:" or "  --> ..."
  "%C\\ -->\\ %f:%l:%c:",
  "%C\\ \\ -->\\ %f:%l:%c:",

  -- Continue multiline messages (lines starting with " |" or "  |")
  "%C\\ \\ |",
  "%C\\ %n\\ |%.%#",
  "%C\\ \\ \\ |%.%#",
  "%C\\ \\ %n\\ |%.%#",

  -- Skip compilation progress and success messages
  "%-GCompiling%.%#",
  "%-GSolc%.%#",
  "%-GCompiler run successful%.%#",
  "%-GNo files changed%.%#",

  -- Skip any other unmatched lines
  "%-G%.%#",
}, ",")
