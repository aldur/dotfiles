-- Compiler definition for Foundry's forge build command
-- This allows parsing forge build errors in the quickfix window
--
-- Usage:
--   :compiler forge
--   :make
--
-- Or use with LazyVim's keybindings for building

vim.bo.makeprg = "forge build"

-- Error format for forge build output
--
-- Forge produces output like:
--   Error (7576): Undeclared identifier.
--    --> src/ErrorTest.sol:8:9:
--     |
--   8 |         undeclaredVar = 5;
--     |         ^^^^^^^^^^^^^
--
--   Warning (2072): Unused local variable.
--    --> src/WarningTest.sol:6:9:
--     |
--   6 |         uint256 x = 5;
--     |         ^^^^^^^^^

vim.bo.errorformat = table.concat({
  -- Match error/warning header with code and message
  "%EError (%n): %m",
  "%WWarning (%n): %m",

  -- Match file location: " --> path/to/file.sol:line:column:"
  "%C\\ -->\\ %f:%l:%c:",

  -- Continue multiline messages (lines starting with " |")
  "%C\\ \\ |",
  "%C\\ %n\\ |%.%#",
  "%C\\ \\ \\ |%.%#",

  -- Skip compilation progress and success messages
  "%-GCompiling%.%#",
  "%-GSolc%.%#",
  "%-GCompiler run successful%.%#",

  -- Skip any other unmatched lines
  "%-G%.%#",
}, ",")
