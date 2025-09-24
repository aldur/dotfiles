if !get(b:, 'jinja_syntax_autocmd_loaded', v:false)
    if luaeval("vim.treesitter.language.get_lang('jinja')") == v:null
        autocmd jinja_syntax_autocmd_loaded FileType <buffer> if !empty(&ft) | setlocal syntax=on | endif
    endif
    let b:jinja_syntax_autocmd_loaded = v:true
endif
