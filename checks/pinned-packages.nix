{
  lib,
  runCommand,
  stdenv,
  # Pins found by utils/discover-pins.nix for this system.
  discovered,
}:

# Asserts that every package fetching a pinned source carries a
# `passthru.updatePin`, and that what it carries is well-formed.
#
# The pin and the instructions for bumping it live in the same file, so there
# is no list to fall out of step with the code; this only enforces that the
# marker is there. A pinned package added without one fails the flake check
# rather than silently never being bumped.
#
# Pure evaluation, so the cheap `nix flake check --no-build` job catches it.

let
  knownKeys = [
    "args"
    "verify"
    "exempt"
  ];

  problems = lib.concatMap (
    e:
    if e.pin == null then
      [
        "`${e.path}` fetches a pinned source but has no `passthru.updatePin`, so nothing ever bumps it"
      ]
    else if !builtins.isAttrs e.pin then
      [ "`${e.path}`: updatePin should be an attribute set" ]
    else
      map (k: "`${e.path}`: unknown updatePin key `${k}`") (
        lib.subtractLists knownKeys (lib.attrNames e.pin)
      )
      ++ lib.optional (
        e.pin ? exempt && (e.pin ? args || e.pin ? verify)
      ) "`${e.path}`: updatePin is exempt, so `args`/`verify` do nothing"
      ++ lib.optional (
        e.pin ? exempt && !lib.isString e.pin.exempt
      ) "`${e.path}`: updatePin.exempt should be the reason, as a string"
  ) discovered;
in

# Concatenated rather than written as an indented string: interpolating newlines
# into one of those does not re-indent, and the report comes out ragged.
lib.throwIf (problems != [ ]) (
  "pinned packages (${stdenv.hostPlatform.system}):\n  "
  + lib.concatStringsSep "\n  " problems
  + "\n\n  Add `passthru.updatePin = { };` next to the pin, or"
  + " `passthru.updatePin.exempt = \"<reason>\";` if it cannot be bumped."
) (runCommand "pinned-packages-check" { } "touch $out")
