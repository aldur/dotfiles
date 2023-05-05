function fish_user_key_bindings
    # Execute this once per mode that emacs bindings should be used in
    fish_default_key_bindings -M insert

    # Without an argument, fish_vi_key_bindings will default to
    # resetting all bindings.
    # The argument specifies the initial mode (insert, "default" or visual).
    fish_vi_key_bindings --no-erase insert

    # Add FZF mappings
    fzf_key_bindings

    # <c-f> accepts suggestion
    for mode in insert default visual
        bind -M $mode \cf forward-char

        bind -M $mode \cp up-or-search
        bind -M $mode \cn down-or-search

        # https://github.com/fish-shell/fish-shell/wiki/Bash-Style-Command-Substitution-and-Chaining-(!!-!$)
        bind -M $mode ! bind_bang
        bind -M $mode '$' bind_dollar
    end
end
