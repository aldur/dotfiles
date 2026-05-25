(_final: prev: {
  fish = prev.fish.overrideAttrs (_old: {
    # https://github.com/NixOS/nix/pull/15638
    dontStrip = true;
  });
})
