-- https://github.com/lukas-reineke/dotfiles/blob/master/vim/lua/efm/shellcheck.lua
return {
    lintCommand = "shellcheck -f gcc -x -",
    lintStdin = true,
    lintFormats = {"%f:%l:%c: %trror: %m", "%f:%l:%c: %tarning: %m", "%f:%l:%c: %tote: %m"},
    lintSource = "shellcheck"
}
