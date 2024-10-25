setlocal commentstring=//\ %s

let b:retab_undo = aldur#whitespace#settab(2)
let b:undo_ftplugin = "setlocal commentstring< " . b:retab_undo
