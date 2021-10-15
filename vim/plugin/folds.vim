set fillchars+=fold:\  " Note that there's a space here.

" https://www.reddit.com/r/neovim/comments/psl8rq/sexy_folds/
" set foldtext=substitute(getline(v:foldstart),'\\t',repeat('\ ',&tabstop),'g').'...'.trim(getline(v:foldend))
set foldtext=substitute(getline(v:foldstart),'\\t',repeat('\ ',&tabstop),'g').'\ ...'

" set foldcolumn=auto
