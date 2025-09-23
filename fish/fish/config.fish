set -g fish_greeting
if status is-interactive
    # Commands to run in interactive sessions can go here

    # By default, `fish` will have per-session history. 
    # This makes it shared.
    history merge
end
