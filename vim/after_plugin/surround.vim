if !exists('g:loaded_surround')
    finish
endif

autocmd vimrc FileType tex call aldur#surrounds#latex()
