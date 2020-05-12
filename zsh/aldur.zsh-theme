# vim:ft=zsh ts=2 sw=2 sts=2
# Aldur's zsh-theme

SEGMENT_SEPARATOR=' '

# Begin a segment
# Takes two arguments, foreground (a colour) and bold (bold or not bold).
prompt_segment() {
  [[ $1 != "none" ]] && echo -n "%F{$1}"
  [[ $2 == "bold" ]] && echo -n "%B"
  echo -n "$3$SEGMENT_SEPARATOR"
  [[ $1 != "none" ]] && echo -n "%f"
  [[ $2 == "bold" ]] && echo -n "%b"
}

# Prompt the user name
prompt_user() {
  prompt_segment red bold "%n"
}

# Prompt the @ separating user and hostname
prompt_at() {
  prompt_segment none false "@"
}

# Prompt the hostname
prompt_hostname() {
  prompt_segment green bold "%m"
}

# Build the context (user@hostname:)
prompt_context() {
  OLD_SEPARATOR=$SEGMENT_SEPARATOR
  SEGMENT_SEPARATOR=''
  prompt_user
  prompt_at
  SEGMENT_SEPARATOR=$OLD_SEPARATOR
  prompt_hostname
}

# Prompt cwd:
prompt_cwd() {
  prompt_segment blue false "%~"
}

# Virtualenv: current working virtualenv
prompt_virtualenv() {
  [[ -n ${VIRTUAL_ENV} && -n ${VIRTUAL_ENV_DISABLE_PROMPT} ]] || return
  prompt_segment yellow false "#${VIRTUAL_ENV:t}"
}

autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*' get-revision true
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' stagedstr '✚'
zstyle ':vcs_info:git:*' unstagedstr '•'
zstyle ':vcs_info:*' formats ' %u%c'
zstyle ':vcs_info:*' actionformats ' %u%c'

precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )

# Git: branch/detached head, dirty status
prompt_git() {
  local ref dirty mode repo_path color
  repo_path=$(git rev-parse --git-dir 2>/dev/null)

  if $(git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    ref=$(git symbolic-ref HEAD 2> /dev/null) || ref="➦ $(git show-ref --head -s --abbrev |head -n1 2> /dev/null)"
    if ! git diff-index --quiet HEAD; then
      color="yellow"
    else
      color="green"
    fi

    if [[ -e "${repo_path}/BISECT_LOG" ]]; then
      mode=" <B>"
    elif [[ -e "${repo_path}/MERGE_HEAD" ]]; then
      mode=" >M<"
    elif [[ -e "${repo_path}/rebase" || -e "${repo_path}/rebase-apply" || -e "${repo_path}/rebase-merge" || -e "${repo_path}/../.dotest" ]]; then
      mode=" >R>"
    fi
    prompt_segment $color false "${ref/refs\/heads\//⎇ }${vcs_info_msg_0_%% }${mode}"
  fi
}

# Prompt a symbol indicating the status:
prompt_status() {
  echo -n "%(?..%F{red}%B✖ %f%b)"
}

# Prompt the newline and the actual prompt:
prompt_newline() {
  prompt_segment blue bold "
    »"
}

# Prompt the time
prompt_time() {
  prompt_segment 105 false "%*"
}

# Prompt background jobs
prompt_jobs() {
  echo -n "%(1j.%F{111}%B⚙ %f%b.)"
}

# Main prompt:
build_prompt() {
  prompt_status
  prompt_jobs
  prompt_time
  prompt_virtualenv
  prompt_context
  prompt_cwd
  prompt_git
  prompt_newline
}

PROMPT='$(build_prompt)'
SPROMPT='zsh: correct %F{red}%R%f to %F{green}%r%f [nyae]? '
