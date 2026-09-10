final: prev: {
  lazygit = prev.lazygit.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./lazygit-user-config-only.patch ];
    postPatch = (old.postPatch or "") + ''
      cp ${./lazygit-user-config-only_test.go} pkg/config/dotfiles_config_test.go
    '';
    doCheck = true;
    preCheck = (old.preCheck or "") + ''
      go test ./pkg/config
    '';
  });
}
