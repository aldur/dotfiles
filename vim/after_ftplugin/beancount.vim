setlocal iskeyword+=:

setlocal formatprg=bean-format
compiler poetry-beancount

command -buffer ReloadCompletions w | lua require'plugins/beancount'.reload_beancount_completions()
