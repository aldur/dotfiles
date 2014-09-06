# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="aldur"

# Example aliases
# alias zshconfig="mate ~/.zshrc"
alias zshconfig="s ~/.zshrc"

# Open specified files in Sublime Text
# "s ." will open the current directory in Sublime
alias s=subl3

# Color LS
# colorflag="-G"
# alias ll="ls -lF ${colorflag}" # all files, in long format
# alias la="ls -laF ${colorflag}" # all files inc dotfiles, in long format
# alias lsd='ls -lF ${colorflag} | grep "^d"' # only directories

## Colorize the grep command output for ease of use (good for log files)##
# alias grep='grep --color=auto'
# alias egrep='egrep --color=auto'
# alias fgrep='fgrep --color=auto'

# Colored up cat!
# You must install Pygments first - "sudo easy_install Pygments"
# alias ccat='pygmentize-3.3 -O style=monokai -f console256 -g'

# Enable aliases to be sudo’ed
# alias sudo='sudo '

# Sublime3 Alias
alias s='subl3'

# Set to this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Uncomment this to disable bi-weekly auto-update checks
# DISABLE_AUTO_UPDATE="true"

# Uncomment to change how often before auto-updates occur? (in days)
# export UPDATE_ZSH_DAYS=13

# Uncomment following line if you want to disable colors in ls
# DISABLE_LS_COLORS="true"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment following line if you want to disable command autocorrection
# DISABLE_CORRECTION="true"

# Uncomment following line if you want red dots to be displayed while waiting for completion
# COMPLETION_WAITING_DOTS="true"

# Uncomment following line if you want to disable marking untracked files under
# VCS as dirty. This makes repository status check for large repositories much,
# much faster.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment following line if you want to  shown in the command execution time stamp
# in the history command output. The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|
# yyyy-mm-dd
# HIST_STAMPS="mm/dd/yyyy"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(z git colored-man zsh-syntax-highlighting history-substring-search)

source $ZSH/oh-my-zsh.sh

# User configuration

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
	export EDITOR='vim'
else
	export EDITOR='vim'
fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
export SSH_KEY_PATH="~/.ssh/dsa_id"

export WORKON_HOME=~/.virtualenvs
source /usr/bin/virtualenvwrapper.sh
