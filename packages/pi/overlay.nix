{ final, prev, unstable }:
let
  piModelsCatalog = final.callPackage ./models-catalog { };
in
{
  # pi releases often; stable nixpkgs lags too far behind, so follow
  # unstable by default. Build it with the stable Node toolchain: slim.nix
  # re-points the stable node paths at the one runtime node of this repo,
  # and an unstable node would stay behind as a twin. Both channels ship
  # Node 24, which strips TS types by default.
  pi-coding-agent = unstable.pi-coding-agent.override { inherit (prev) buildNpmPackage; };

  piPlugins = {
    # final.callPackage: the build-time checks must see the same
    # pi-coding-agent (above) that the wrapper runs.
    pi-llama = final.callPackage ./plugins/pi-llama.nix { };
    pi-no-docs = final.callPackage ./plugins/pi-no-docs { };
    pi-startup-header = prev.callPackage ./plugins/pi-startup-header { };
    pi-openai-discovery = final.callPackage ./plugins/pi-openai-discovery {
      modelsCatalog = piModelsCatalog;
    };
    pi-statusline = prev.callPackage ./plugins/pi-statusline { };
    pi-prompt-stash = final.callPackage ./plugins/pi-prompt-stash { };
    pi-daybreak = final.callPackage ./plugins/pi-daybreak { };
    pi-subagent = final.callPackage ./plugins/pi-subagent { };
    pi-system-prompt = final.callPackage ./plugins/pi-system-prompt { };
    pi-throughput = final.callPackage ./plugins/pi-throughput { };
  };
  pi = prev.callPackage ./pi.nix {
    inherit (final) playwright-lazy;
    plugins = final.piPlugins;
    modelsCatalog = piModelsCatalog;
  };
}
