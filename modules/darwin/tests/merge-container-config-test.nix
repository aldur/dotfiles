# Tests for merge-container-config.py — the activation-time merge that keeps
# `machine.homeMount = "none"` in Apple `container`'s config.toml. Wired into
# `checks` in flake.nix. Run with:
#   nix build .#checks.<system>.merge-container-config
{
  stdenv,
  python3,
}:
let
  python = python3.withPackages (ps: [ ps.tomlkit ]);
  script = ../merge-container-config.py;
in
stdenv.mkDerivation {
  name = "merge-container-config-test";

  buildCommand = ''
    set -euo pipefail

    merge() { ${python}/bin/python3 ${script} "$1"; }

    echo "=== Case 1: file does not exist -> created with our setting ==="
    C1="$PWD/c1.toml"
    [ ! -e "$C1" ]
    merge "$C1"
    grep -q '\[machine\]'          "$C1"
    grep -q 'homeMount = "none"'   "$C1"
    echo "  ok"

    echo "=== Case 2: file exists -> our key merged in, everything else kept ==="
    C2="$PWD/c2.toml"
    printf '# user comment\n[machine]\nfoo = "bar"\n\n[network]\nx = 1\n' > "$C2"
    merge "$C2"
    grep -q '# user comment'       "$C2"   # comment preserved
    grep -q 'foo = "bar"'          "$C2"   # sibling key preserved
    grep -q '\[network\]'          "$C2"   # unrelated table preserved
    grep -q 'x = 1'                "$C2"   #   ... and its key
    grep -q 'homeMount = "none"'   "$C2"   # our key added
    echo "  ok"

    echo "=== Case 3: conflict -> our value overwrites the existing one ==="
    C3="$PWD/c3.toml"
    printf '[machine]\nhomeMount = "all"\n' > "$C3"
    merge "$C3"
    grep -q 'homeMount = "none"'   "$C3"   # our value wins
    ! grep -q '"all"'              "$C3"   # old value gone
    # exactly one homeMount line (no duplicate appended)
    [ "$(grep -c 'homeMount' "$C3")" -eq 1 ]
    echo "  ok"

    echo "=== Idempotency: re-running on Case 2 changes nothing ==="
    before="$(cat "$C2")"
    merge "$C2"
    [ "$before" = "$(cat "$C2")" ]
    echo "  ok"

    mkdir -p "$out"
    echo "all merge-container-config tests passed" > "$out/result"
  '';
}
