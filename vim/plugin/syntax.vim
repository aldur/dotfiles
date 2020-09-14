" Highlight TODO, FIXME, NOTE, etc.
autocmd vimrc WinEnter,VimEnter * if !exists('w:match_id_todo') | let w:match_id_todo = matchadd('Todo',  '\zs\(TODO\|FIXME\|CHANGED\|XXX\|BUG\|HACK\)') | endif
autocmd vimrc WinEnter,VimEnter * if !exists('w:match_id_debug') |let w:match_id_debug = matchadd('Debug', '\zs\(NOTE\|INFO\|IDEA\|DEBUG\)') | endif
