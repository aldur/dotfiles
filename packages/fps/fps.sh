#!/usr/bin/env bash

set -euo pipefail

# @describe Interactive process picker: `ps` wrapped with `fzf`
#
# <ctrl-k> kills the highlighted process (SIGKILL); <enter> prints the
# highlighted PID and exits.

eval "$(argc --argc-eval "$0" "$@")"

ps -eo pid,user,%cpu,%mem,args \
  | fzf --header-lines=1 \
        --footer "<c-k> kills PID; <cr> prints PID" \
        --bind 'ctrl-k:execute(kill -KILL {1})+abort,enter:become(echo {1})'
