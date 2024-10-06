abbr -a gc git commit
abbr -a gco "git checkout (git branch --all | fzf | tr -d '[:space:]')"
abbr -a gd git diff
abbr -a gp git push
abbr -a gst git status
abbr -a ls gls --color=tty
abbr -a ssh autossh
abbr -a ta tmux -CC new -ADs
abbr -a tls tmux ls
abbr -a vim neovide

# Override macOS ssh-agent with yubikey-agent
# We need to do this here since macOS sets a universal variable, so we shadow
# it this way.
# set -gx SSH_AUTH_SOCK /usr/local/var/run/yubikey-agent.sock

# Override macOS ssh-agent with Secretive (installed from `brew`)
set -x SSH_AUTH_SOCK $HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
