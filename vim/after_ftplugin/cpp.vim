if has('macunix')
    " Disable GCC and clang on macOS
    let b:ale_linters_ignore = ['gcc', 'clang']
end

if executable('astyle')
    function! AStyle(buffer) abort
        return { 'command': 'astyle --style=google --indent=spaces=4 --max-code-length=100 --break-blocks --break-one-line-headers --add-one-line-braces --attach-return-type --pad-header --pad-oper --pad-comma --unpad-paren --align-pointer=name --align-reference=name --stdin=%t' }
    endf
    let b:ale_fixers = ['AStyle']
endif
