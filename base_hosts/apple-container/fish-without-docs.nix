{
  fish,
  runCommand,
  removeReferencesTo,
}:
# Fish embeds its HTML manual's path in its binaries. Repack the cached
# shell without that reference; `help` falls back to the online manual.
# Keep the package name for equal-length rewrites of its own prefix.
runCommand fish.name
  {
    nativeBuildInputs = [ removeReferencesTo ];
    inherit (fish) meta;
    passthru.shellPath = fish.shellPath;
  }
  ''
    cp -a ${fish} $out
    chmod -R u+w $out
    find $out -type f -exec sed -i "s|${fish}|$out|g" {} +
    find $out -type f -exec remove-references-to -t ${fish.doc} {} +
    ! grep -rF ${fish} $out
    ! grep -rF ${fish.doc} $out
    test -z "$(find $out -type l -lname '${fish}*')"
  ''
