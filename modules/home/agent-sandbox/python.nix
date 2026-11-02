{ pkgs }:
pkgs.runCommand "agent-sandbox-python" {
  nativeBuildInputs = [ pkgs.patchelf pkgs.removeReferencesTo ];
} ''
  cp -a ${pkgs.python3} "$out"
  chmod -R u+w "$out"
  rm -rf "$out"/include "$out"/lib/python3.*/config-* \
    "$out"/lib/python3.*/idlelib "$out"/lib/python3.*/test
  # Point the copied executable to its own library before removing references.
  patchelf --set-rpath "$out/lib" "$(readlink -f "$out/bin/python3")"
  find "$out" -type f -exec remove-references-to -t ${pkgs.python3} {} +
  "$out/bin/python3" -I ${./launch.py} --help > /dev/null
  "$out/bin/python3" -I ${./network.py} --help > /dev/null
''
