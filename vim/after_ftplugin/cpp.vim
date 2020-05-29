if has('macunix')
    " Disable GCC and clang on macOS
    let b:ale_linters_ignore = ['gcc', 'clang']
end

if executable('astyle')
    let b:ale_fixers = ['aldur#ale_fixers#astyle']
endif
