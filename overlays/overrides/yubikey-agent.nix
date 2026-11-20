final: prev: {
  yubikey-agent = prev.yubikey-agent.overrideAttrs (old: {
    # Used a patch instead of overriding the source so that it will keep
    # working (or explicitly breaking) on upstream updates.
    patches = (old.patches or [ ]) ++ [
      (prev.fetchurl {
        # The commit page sometimes returns HTTP 503. The API gives the
        # same bytes when the request asks for the patch media type.
        urls = [
          "https://github.com/aldur/yubikey-agent/commit/f7a6769fd832a867e62228c8ddb0133174db64bf.patch"
          "https://api.github.com/repos/aldur/yubikey-agent/commits/f7a6769fd832a867e62228c8ddb0133174db64bf"
        ];
        curlOptsList = [
          "-H"
          "Accept: application/vnd.github.patch"
        ];
        hash = "sha256-swQb3N89yAJSQ4pkUq2DDKvEFBlzhr/tbNMdC2p60VE=";
      })
    ];
  });
}
