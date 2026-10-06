# Guard for temporary package overrides (backports, pins to unreleased
# commits). Returns `replacement` while nixpkgs ships a version older than
# `version`, and aborts once it reaches that cutoff. By default the cutoff
# follows the replacement's version; backports that keep the package version
# must specify the first upstream release that needs review explicitly.
{
  package,
  replacement,
  version ? replacement.version,
  note ? "Re-evaluate whether the override is still needed.",
}:
if builtins.compareVersions package.version version < 0 then
  replacement
else
  throw ''
    ${package.pname or package.name} override expires at ${version}, but nixpkgs now ships ${package.version}.
    ${note}''
