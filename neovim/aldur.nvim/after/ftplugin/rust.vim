" https://github.com/lilydjwg/dotvim/blob/master/ftplugin/rust.vim
let b:surround_{char2nr("d")} = "dbg!(\r)"

setlocal nofoldenable
setlocal foldmethod=expr
setlocal foldexpr=nvim_treesitter#foldexpr()

let g:cargo_makeprg_params = 'build'  " Run `cargo build` with shortcut
compiler cargo_direnv
