function! FormatShellCommand(buffer) abort
    return { 'command': 'cat %t | python3 ~/.vim/scripts/format_shell_cmd.py' }
endf
let b:ale_fixers = ['FormatShellCommand']
