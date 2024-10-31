if executable('rg')
    set grepprg=rg\ --vimgrep\ --no-heading\ --smart-case
    set grepformat=%f:%l:%c:%m,%f:%l:%m
elseif executable('ag')
    set grepprg=ag\ --vimgrep\ $*
    set grepformat=%f:%l:%c:%m
elseif executable('ack')
    set grepprg=ack\ -k
endif

" https://gist.github.com/romainl/56f0c28ef953ffc157f36cc495947ab3
" Instant grep + quickfix

" s/expandcmd/expand/g because nvim does not support `expandcmd`
function! Grep(...) abort
	return system(join([&grepprg] + [expand(join(a:000, ' '))], ' '))
endfunction

command! -nargs=+ -complete=file_in_path -bar Grep  cgetexpr Grep(<f-args>)
command! -nargs=+ -complete=file_in_path -bar LGrep lgetexpr Grep(<f-args>)

call aldur#abbr#cnoreabbrev("grep", "Grep")
call aldur#abbr#cnoreabbrev("lgrep", "LGrep")

" Clear lists when either command is executed.
autocmd vimrc QuickFixCmdPost cgetexpr cwindow
autocmd vimrc QuickFixCmdPost lgetexpr lwindow
