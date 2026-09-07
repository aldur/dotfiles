final: prev: {
  gvproxy = prev.gvproxy.overrideAttrs (old: {
    # See the patch header.
    patches = (old.patches or [ ]) ++ [ ./gvproxy-guest-isolation.patch ];
  });
}
