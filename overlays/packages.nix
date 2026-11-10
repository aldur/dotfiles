{ self }:
final: prev:
let
  # `legacyPackages` reuses the flake's memoized, un-overlaid package set.
  unstable = self.inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system};
in
{
  nomicfoundation-solidity-language-server =
    prev.callPackage
      ../packages/nomicfoundation-solidity-language-server/nomicfoundation-solidity-language-server.nix
      { };

  solidity-docset = prev.callPackage ../packages/solidity-docset { };

  gpg-encrypt = prev.callPackage ../packages/gpg-encrypt/gpg-encrypt.nix { };
  totp-cli = final.callPackage ../packages/totp-cli-ephemeral { inherit (prev) totp-cli; };

  # Headless: they only shell out to `gs`, and the default ghostscript build
  # carries X11 and gtk (~95M) for a window no wrapper ever opens.
  shrink-pdf = prev.callPackage ../packages/shrink-pdf { ghostscript = prev.ghostscript_headless; };
  flatten-pdf = prev.callPackage ../packages/flatten-pdf { ghostscript = prev.ghostscript_headless; };
  watermark-pdf = prev.callPackage ../packages/watermark-pdf { };
  split-pdf = prev.callPackage ../packages/split-pdf { };
  totp-qr-decode = prev.callPackage ../packages/totp-qr-decode { };
  flake-lock-cooldown = prev.callPackage ../packages/flake-lock-cooldown { };
  git-verify-ssh = final.callPackage ../packages/git-verify-ssh {
    git = final.gitMinimal-runtime;
  };
  update-pins = prev.callPackage ../packages/update-pins { };
  neovim-nightly = prev.callPackage ../packages/neovim-nightly { };

  aldurs-dotfiles-version = prev.callPackage ../packages/aldurs-dotfiles-version { inherit self; };
  faraday = prev.callPackage ../packages/faraday { };
  usrbin = prev.callPackage ../packages/usrbin { };
  fps = prev.callPackage ../packages/fps { };
  lstrip = prev.callPackage ../packages/lstrip { };
  nospace = prev.callPackage ../packages/nospace { };
  trim = prev.callPackage ../packages/trim { };
  claude-skills = prev.callPackage ../packages/claude-skills { };
  remarks = prev.callPackage ../packages/remarks { };
  tmux-palette = prev.callPackage ../packages/tmux-palette { };
  tcopy = prev.callPackage ../packages/tcopy { };
  lazyvim-popup = prev.callPackage ../packages/lazyvim-popup { };
  lazygit-popup = prev.callPackage ../packages/lazygit-popup { };
  # Stable keeps pnpm_10 at insecure 10.34.0 for compatibility. Taskmd's
  # lockfile works with the maintained 10.x release from unstable.
  taskmd = prev.callPackage ../packages/taskmd { inherit (unstable) pnpm_10; };
  taskmd-ui = final.callPackage ../packages/taskmd-ui { };

  llmcat = prev.callPackage ../packages/llmcat/llmcat.nix { };

  # AppArmor unix socket rules on a kernel newer than 6.16 need parser 5.
  # Stable ships 4, which downgrades those rules with a warning.
  apparmor-parser = import ../utils/override-until-upgrade.nix {
    package = prev.apparmor-parser;
    version = "5.0.0";
    note = "Drop the unstable apparmor-parser once stable ships version 5.";
    replacement = unstable.apparmor-parser;
  };

  agent-log = final.callPackage ../packages/agent-log { };
  tavily-cli = final.callPackage ../packages/tavily-cli { };

  llm-mlx = prev.callPackage ../packages/llm-mlx { };
  llmWithPlugins = (prev.python3.withPackages (
    ps:
    [
      ps.llm
      ps.llm-ollama
      ps.llm-gguf
      ps.llm-openrouter
      ps.llm-docs
      ps.llm-llama-server
    ]
    ++ prev.lib.optional (
      prev.stdenv.hostPlatform.isDarwin && prev.stdenv.hostPlatform.isAarch64
    ) final.llm-mlx
  )).override {
    makeWrapperArgs = [ "--set HF_HUB_DISABLE_TELEMETRY 1" ];
  };

  markdownlint-cli2 = final.callPackage ../packages/markdownlint-cli2 {
    markdownlint-cli2-unwrapped = prev.markdownlint-cli2;
  };

  uvc-util = prev.callPackage ../packages/uvc-util { };
  c920-defaults = final.callPackage ../packages/c920-defaults { };
}
// import ../packages/pi/overlay.nix { inherit final prev unstable; }
