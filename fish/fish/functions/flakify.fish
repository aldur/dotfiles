function flakify
    if not test -e flake.nix
        nix flake new -t github:nix-community/nix-direnv .
    else if not test -f .envrc
        echo "use flake" > .envrc
        direnv allow
    end
    exec $EDITOR flake.nix
end
