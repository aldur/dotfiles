compiler poetry-beancount

setlocal formatprg=bean-format

setlocal comments=b:;
setlocal commentstring=;%s

setlocal iskeyword+=:

command -buffer ReloadCompletions w | lua require'plugins/beancount'.reload_beancount_completions()
