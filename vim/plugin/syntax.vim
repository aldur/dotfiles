" Highlight TODO, FIXME, NOTE, etc.
autocmd vimrc Syntax * call matchadd('Todo',  '\zs\(TODO\|FIXME\|CHANGED\|XXX\|BUG\|HACK\)')
autocmd vimrc Syntax * call matchadd('Debug', '\zs\(NOTE\|INFO\|IDEA\|DEBUG\)')
