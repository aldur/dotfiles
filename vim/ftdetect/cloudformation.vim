" This will make `*/cloudformation/*.yaml` file inherit from `yaml`, so we can run
" specific linters.
" See `ftdetect/env.vim`.
autocmd vimrc BufRead,BufNewFile */cloudformation/*.yaml set filetype=yaml.cloudformation
