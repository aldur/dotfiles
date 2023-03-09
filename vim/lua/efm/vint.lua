-- https://github.com/lukas-reineke/dotfiles/blob/master/vim/lua/efm/vint.lua
return {
    lintCommand = "vint --enable-neovim --style-problem -",
    lintStdin = true,
    lintFormats = {"%f:%l:%c: %m"},
    lintSource = "vint"
}
