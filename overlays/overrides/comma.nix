_final: prev: {
  comma = prev.comma.overrideAttrs (old: {
    # Stop at the nearest shell before hidepid blocks an older ancestor.
    patches = (old.patches or [ ]) ++ [ ./comma-nearest-shell.patch ];
  });
}
