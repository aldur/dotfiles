command! -nargs=* Glg Git! log --graph --pretty=format:'%h (%ad)%d %s <%an>' --abbrev-commit --date=iso-local <args>

cnoreabbrev Gbrowse GBrowse
