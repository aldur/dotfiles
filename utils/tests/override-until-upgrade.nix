let
  guard = import ../override-until-upgrade.nix;
  allows =
    upstream: cutoff:
    (guard {
      package = {
        pname = "test";
        version = upstream;
      };
      replacement = {
        version = cutoff;
        marker = "replacement";
      };
    }).marker == "replacement";
  rejects =
    upstream: cutoff:
    !(builtins.tryEval (guard {
      package = {
        pname = "test";
        version = upstream;
      };
      replacement = {
        version = cutoff;
      };
    })).success;
  explicitCutoff =
    upstream: cutoff:
    builtins.tryEval (guard {
      package = {
        pname = "backport";
        version = upstream;
      };
      version = cutoff;
      # A backport keeps the old version; its cutoff must take precedence.
      replacement = {
        version = upstream;
        marker = "backport";
      };
    });
in
assert allows "0.87.1" "1.0.0";
assert allows "0.99.1" "1.0.0";
assert rejects "1.0.0" "1.0.0";
assert rejects "1.0.1" "1.0.0";
assert allows "0.9.0" "0.10.0";
assert rejects "0.10.0" "0.9.0";
assert allows "0.0.5-unstable-2026-07-26" "0.0.5-unstable-2026-07-27";
assert rejects "0.0.5-unstable-2026-07-27" "0.0.5-unstable-2026-07-27";
assert rejects "0.0.5-unstable-2026-07-28" "0.0.5-unstable-2026-07-27";
assert (explicitCutoff "4.9.0" "5.0.0").value.marker == "backport";
assert !(explicitCutoff "5.0.0" "5.0.0").success;
assert !(explicitCutoff "5.1.0" "5.0.0").success;
assert (explicitCutoff "3.1.2" "3.2.0").success;
assert !(explicitCutoff "3.2.0" "3.2.0").success;
assert (explicitCutoff "2.37.1" "2.37.2").success;
assert !(explicitCutoff "2.37.2" "2.37.2").success;
true
