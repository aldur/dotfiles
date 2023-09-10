function fish_prompt --description 'Write out the prompt'
    set -l last_pipestatus $pipestatus
    set -l last_status $status
    set -l normal (set_color normal)

    # Color the prompt differently when we're root
    set -l color_cwd $fish_color_cwd
    set -l prefix
    if contains -- $USER root toor
        if set -q fish_color_cwd_root
            set color_cwd $fish_color_cwd_root
        end
    end

    # If we're running via SSH, change the host color.
    set -l color_host $fish_color_host
    if set -q SSH_TTY
        set color_host $fish_color_host_remote
    end

    # Git prompt
    ## Enable colors
    set -g __fish_git_prompt_showcolorhints true
    # set -g __fish_git_prompt_color_stagedstate yellow
    # set -g __fish_git_prompt_color_dirtystate yellow

    ## Show dirty state
    set -g __fish_git_prompt_showdirtystate true

    set -g __fish_git_prompt_char_dirtystate •
    set -g __fish_git_prompt_char_stagedstate ✚

    # Virtualenv
    set -l virtualenv ""
    if set -q VIRTUAL_ENV
        set -a virtualenv (set_color yellow) "#" (basename "$VIRTUAL_ENV") " "
    end

    set -l nested ""
    if test $SHLVL -gt 1
        set -a nested (set_color yellow) "↳" " "
    end

    # Time
    set -l time (set_color "8787ff") (date +'%T') " " 

    # Write pipestatus
    set -l prompt_status ""
    if test (count $pipestatus) -eq 1 && test $last_status -eq 1
        set -a prompt_status (set_color --bold $fish_color_status) "✖ "
    else
        set -a prompt_status (__fish_print_pipestatus "" " " "|" (set_color $fish_color_status) (set_color --bold $fish_color_status) $last_pipestatus)
    end 

    echo -e -n -s $prompt_status $nested $virtualenv $time (set_color $fish_color_user) "$USER" $normal @ (set_color $color_host) (prompt_hostname) $normal ' ' (set_color $color_cwd) (prompt_pwd) $normal (fish_git_prompt) $normal (set_color --bold blue) "
    » "
end
