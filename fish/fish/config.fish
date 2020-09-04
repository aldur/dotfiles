abbr -a gc git commit
abbr -a gco "git checkout (git branch --all | fzf | tr -d '[:space:]')"
abbr -a gd git diff
abbr -a gp git push
abbr -a gst git status
abbr -a ls gls --color=tty
abbr -a ssh autossh
abbr -a ta tmux -CC new -ADs
abbr -a tls tmux ls
abbr -a vim vimr

# Source Google Cloud SKD
if test -f /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc
    source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc
end
