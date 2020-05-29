function! aldur#ale_fixers#format_shell_command(buffer) abort
    return { 'command': 'cat %t | python3 ~/.vim/scripts/format_shell_cmd.py' }
endf

function! aldur#ale_fixers#astyle(buffer) abort
    return { 'command': 'astyle --style=google --indent=spaces=4 --max-code-length=100 --break-blocks --break-one-line-headers --add-one-line-braces --attach-return-type --pad-header --pad-oper --pad-comma --unpad-paren --align-pointer=name --align-reference=name --stdin=%t' }
endf

function! aldur#ale_fixers#bibtool(buffer) abort
    return { 'command': 'bibtool %t' }
endf
