function flakify
    if not test -e flake.nix
        cp $HOME/.config/fish/functions/template.flake.nix flake.nix
    end
    if not test -f .envrc
        echo "use flake" > .envrc && direnv allow
    end
    if test -e .git
        git add flake.nix
    end
     nvim flake.nix
end
