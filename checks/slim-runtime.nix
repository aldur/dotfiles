{
  runCommand,
  python3,
  stdenv,
  lib,
  lua5_4,
  pandoc-runtime,
  pi,
  ripgrep-all,
}:
runCommand "slim-runtime" { nativeBuildInputs = [ python3 stdenv.cc ]; } ''
  export HOME=$TMPDIR/home
  mkdir -p "$HOME"
  # A native Lua module catches loss of dynamically resolved Lua symbols.
  cat > native.c <<'EOF'
  #include <lua.h>
  int luaopen_native(lua_State *L) {
    lua_pushstring(L, "native module loaded");
    return 1;
  }
  EOF
  cc -shared -fPIC -I${lib.getDev lua5_4}/include native.c -o native.so
  python3 ${./slim-runtime.py} ${pandoc-runtime}/bin/pandoc ${pi}/bin/pi ${ripgrep-all}/bin/rga
  touch "$out"
''
