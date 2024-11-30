function! aldur#find_root#find_root() abort
    if aldur#find_root#pwd_is_root()
        return getcwd()
    endif

    if &filetype ==# 'fugitive'
        " If `fugitive` buffer,
        " expand(%:p:h, 1) gets us fugitive://dir/.git which doesn't work e.g.
        " if opening a terminal.
        " Instead, we just read the location of the `.git` directory and get
        " its parent.
        " NOTE: Untested if using a `.git` folder under another name.
        return fnamemodify(FugitiveGitDir(), ':p:h:h')
    endif

    let l:base = '%:p:h'

    if &filetype ==# 'NvimTree'
        let l:base = luaeval('require("nvim-tree.core").get_cwd()')
    endif

    let l:base = expand(l:base, 1)

    " TODO: we might need to do the same for oil.nvim

    try
        " We're using gutentags#get_project_root for the task.
        let l:root = gutentags#get_project_root(l:base)
    catch
        let l:root = l:base
    endtry

    " If it's a terminal or a health window, then we default to cwd
    if l:root =~# 'term://' || expand('%') =~# 'health://'
        return getcwd()
    endif

    return l:root
endfunction

function! aldur#find_root#cd_to_root() abort
    let l:root = aldur#find_root#find_root()
    execute 'cd ' l:root
    pwd
endfunction

function! aldur#find_root#lcd_to_root() abort
    let l:root = aldur#find_root#find_root()
    execute 'lcd ' l:root
    pwd
endfunction

" When toggled, overrides `root` directory with cwd.
" All tools relying on `root` directory (eg FZF), will instaed use cwd.
function! aldur#find_root#toggle_override_root_with_pwd() abort
    if !exists('w:pwd_is_root')
        let w:pwd_is_root = v:false
    endif

    let w:pwd_is_root = !w:pwd_is_root
endfunction

function! aldur#find_root#pwd_is_root() abort
    return get(w:, 'pwd_is_root', 0) == 1
endfunction
