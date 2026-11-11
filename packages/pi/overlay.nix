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
  pi-coding-agent = import ../../utils/override-until-upgrade.nix {
    package = unstable.pi-coding-agent;
    # The nixpkgs recipe for 1.5.0 does not copy the workspace package
    # packages/schema (@earendil-works/pi-schema) into node_modules. pi-ai
    # imports it, thus pi-statusline, pi-subagent and the plugin tests fail
    # with ERR_MODULE_NOT_FOUND.
    #
    # nixpkgs master has the correction since 1.5.2, in
    # pkgs/by-name/pi/pi-coding-agent/package.nix. On 2026-11-11 the
    # nixos-unstable channel, which flake.lock follows, did not have it.
    # Remove this override when `nix flake update` brings a nixpkgs-unstable
    # that lists pi-schema in that file. The guard stops the evaluation at
    # the first newer version as a reminder.
    version = "1.5.1";
    note = "Remove the pi-schema copy in packages/pi/overlay.nix if pkgs/by-name/pi/pi-coding-agent/package.nix of nixpkgs-unstable copies packages/schema.";
    replacement =
      (unstable.pi-coding-agent.override { inherit (prev) buildNpmPackage; }).overrideAttrs
        (old: {
          postInstall = ''
            schema="$out/lib/node_modules/pi-monorepo/node_modules/@earendil-works/pi-schema"
            rm "$schema"
            cp -r packages/schema "$schema"
          ''
          + old.postInstall;
        });
  };

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
