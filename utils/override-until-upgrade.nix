# Guard for temporary package overrides (backports, pins to unreleased
# commits). Returns `replacement` while nixpkgs still ships `version` of
# `package`, and aborts evaluation the moment the shipped version
# changes, so the override gets re-evaluated instead of silently
# outliving its purpose.
{
  package,
  version,
  replacement,
  note ? "Re-evaluate whether the override is still needed.",
}:
if package.version == version then
  replacement
else
  throw ''
    ${package.pname or package.name} was overridden while nixpkgs shipped ${version}, but nixpkgs now ships ${package.version}.
    ${note}''
