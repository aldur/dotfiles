" Highlight TODO, FIXME, NOTE, XXX etc.
autocmd vimrc WinEnter,VimEnter * if !exists('w:match_id_todo') | let w:match_id_todo = matchadd('Todo',  '\zs\(TODO\|FIXME\|CHANGED\|LINKME\)') | endif
autocmd vimrc WinEnter,VimEnter * if !exists('w:match_id_note') |let w:match_id_note = matchadd('Note', '\zs\(NOTE\|INFO\|IDEA\|EDIT\)') | endif
autocmd vimrc WinEnter,VimEnter * if !exists('w:match_id_debug') |let w:match_id_debug = matchadd('Debug', '\zs\(XXX\|BUG\|DEBUG\|HACK\|WARN\|WARNING\)') | endif
autocmd vimrc WinEnter,VimEnter * if !exists('w:match_id_done') |let w:match_id_done = matchadd('Done', '\zs\(DONE\)') | endif
