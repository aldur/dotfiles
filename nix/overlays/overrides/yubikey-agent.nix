final: prev: {
  yubikey-agent = prev.yubikey-agent.overrideAttrs (old: {
    # Used a patch instead of overriding the source so that it will keep
    # working (or explicitly breaking) on upstream updates.
    patches = (old.patches or [ ]) ++ [
      (prev.fetchurl {
        url = "https://github.com/aldur/yubikey-agent/commit/f7a6769fd832a867e62228c8ddb0133174db64bf.patch";
        hash = "sha256-swQb3N89yAJSQ4pkUq2DDKvEFBlzhr/tbNMdC2p60VE=";
      })
    ];
  });
}
