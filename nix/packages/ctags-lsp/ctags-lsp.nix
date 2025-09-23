{
  buildGoModule,
  fetchFromGitHub,
  symlinkJoin,
  universal-ctags,
}:
let
  name = "ctags-lsp";
  version = "5c22d0b1ee30d9c1e65c89a5f0eab74ded7dbd7f";
  ctags-lsp = buildGoModule {
    inherit version;
    name = "${name}-unwrapped";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = name;
      rev = version;
      hash = "sha256-z7fgS2iQ7Wgq+YDdub6Pn82XjfqFvLWBUceCT+jcnYI=";
    };

    vendorHash = null;

    ldflags = [
      "-X main.version=${version}"
    ];
  };
  # ctags-lsp-log = (
  #   writeShellApplication {
  #     inherit name;
  #
  #     runtimeInputs = [
  #       ctags-lsp
  #     ];
  #
  #     text = ''
  #       coproc LSP_SERVER { ctags-lsp 2> /tmp/error.log; }
  #
  #       # first some necessary file-descriptors fiddling
  #       exec {srv_input}>&"''${LSP_SERVER[1]}"-
  #       exec {srv_output}<&"''${LSP_SERVER[0]}"-
  #
  #       # background commands to relay normal stdin/stdout activity
  #       tee /tmp/input.log <&0 >&''${srv_input} &
  #       tee /tmp/output.log <&''${srv_output} &
  #
  #       while true; do sleep 86400; done
  #
  #     '';
  #   }
  # );
in
symlinkJoin {
  inherit name;
  paths = [
    universal-ctags
    ctags-lsp
  ];
}
