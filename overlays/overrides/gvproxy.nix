final: prev: {
  gvproxy = prev.gvproxy.overrideAttrs (old: {
    # See the patch headers. The second applies on top of the first.
    patches = (old.patches or [ ]) ++ [
      ./gvproxy-guest-isolation.patch
      ./gvproxy-host-isolation.patch
    ];
  });
}
