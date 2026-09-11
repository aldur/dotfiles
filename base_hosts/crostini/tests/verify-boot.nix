{ pkgs, crostini }:
let
  shared = import "${crostini}/tests/lib.nix" { inherit (pkgs) lib; };
  check = shared.mkCheckProbes pkgs [
    "user-manager active$"
    "DONE$"
    "result 0$"
  ];
in
pkgs.runCommand "baguette-boot-verifier" { } ''
  cat > good.log <<'EOF'
  PROBE user-manager active
  PROBE kernel fixture-kernel
  PROBE root btrfs 200
  PROBE DONE
  PROBE result 0
  EOF
  echo fixture-kernel > release
  verify() {
    bash ${./verify-boot.sh} "$1" "$2" ${check} release 100
  }
  reject() {
    if verify "$1" "$2"; then
      echo "FAIL: accepted $1 $2" >&2
      exit 1
    fi
  }
  verify 0 good.log
  sed 's/$/\r/' good.log > crlf.log
  verify 0 crlf.log
  reject 124 good.log # Timeout after all probes were printed.
  reject 1 good.log   # Failed shutdown after all probes were printed.
  sed '/PROBE DONE/d' good.log > truncated.log
  reject 0 truncated.log
  sed 's/result 0/result 1/' good.log > failed.log
  reject 0 failed.log
  sed 's/user-manager active/user-manager inactive/' good.log > no-session.log
  reject 0 no-session.log
  sed 's/fixture-kernel/wrong-kernel/' good.log > wrong-kernel.log
  reject 0 wrong-kernel.log
  sed 's/btrfs 200/btrfs 100/' good.log > no-resize.log
  reject 0 no-resize.log
  touch "$out"
''
