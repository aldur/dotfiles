{
  lib,
  stdenv,
  runCommand,
  closureInfo,
  # Every derivation the flake exports for this system — packages, the
  # overlay's tools and slim.nix's repacks — discovered by ./default.nix
  # rather than enumerated here.
  packagesUnderGuard,
  # Attr names before platform filtering: staleness is judged against
  # these, so an entry for a linux-only package doesn't fail darwin eval.
  knownNames,
}:

# overlays/slim.nix strips cached derivations by repacking them; the
# technique's failure mode is silent: a rewrite that stops matching after
# a bump becomes a no-op, the build still succeeds, and the bloat quietly
# returns. The repack builders assert their own swaps; this guards the
# closure end. Every discovered derivation gets a size budget — unlisted
# ones must fit the default, so a new heavy package fails loudly until it
# gets a conscious entry — and the known regressions are pinned by name.
# Grows legitimately? Re-measure and raise the budget here.
#
# ./default.nix wires this check up on Linux only, matching the repacks
# themselves: darwin ships the stock packages, so these budgets have
# nothing to say there.

let
  defaultBudgetMiB = 150;

  # Budgets are measured on x86_64-linux; other architectures run larger
  # across the board (aarch64 CI measured ~8-15% over x86 for the same
  # closures), so every budget stretches by this factor off the baseline
  # rather than growing per-entry guesswork. Percent, applied in-script.
  archFactor = if stdenv.hostPlatform.system == "x86_64-linux" then 100 else 115;

  # MiB, ~10% above measured on x86_64-linux (2026-08). Only packages
  # that outgrow the default belong here; stale names fail the eval.
  budgets = {
    lazyvim = 1370;
    lazyvim-light = 250;
    lazyvim-nightly = 1390;
    remarks = 700;
    llm = 650; # the flake alias of llmWithPlugins
    llmWithPlugins = 650;
    pi = 455;
    pi-coding-agent = 415;
    # A node interpreter and one stdlib-only script; it is nodejs-slim-runtime
    # plus a wrapper, so it inherits that entry's budget.
    llama-wiretap = 200;
    ripgrep-all = 650;
    # Not uniform drift: ARM chromium is ~40% bigger than x86's (CI
    # measured 1040 there against ~730 here), beyond what archFactor
    # models.
    playwright-mcp = if stdenv.hostPlatform.isAarch64 then 1000 else 805;
    watermark-pdf = 330;
    nomicfoundation-solidity-language-server = 270;
    nodejs-slim-runtime = 200;
    marksman = 180;
    basedpyright = 230;
    # 0.146 adds the codex-code-mode-host helper binary (63M).
    codex = 470;
    markdownlint-cli2 = 220;
    prettierd = 210;
    tiktoken = 260;
    vscode-langservers-extracted = 200;
    vtsls = 240;
    tesseract-lite = 170;
  };

  # Name fragments that must never (re)appear in a closure.
  forbidden = {
    remarks = [ "-all$" ]; # the full-language tessdata, 1G
    shrink-pdf = [
      "gtk+3"
      "-x11"
    ];
    flatten-pdf = [
      "gtk+3"
      "-x11"
    ];
    ripgrep-all = [
      "gtk+3"
      "-sdl2"
    ];
    playwright-mcp = [
      "firefox"
      "webkit"
      # The full nodejs join, re-pointed to nodejs-slim-runtime.
      "-npm$"
      "corepack"
    ];
  };

  names = builtins.attrNames packagesUnderGuard;
  stale = lib.subtractLists knownNames (builtins.attrNames (budgets // forbidden));
in

assert lib.assertMsg (
  stale == [ ]
) "slim-closures: entries without a matching package: ${toString stale}";

runCommand "slim-closures" { } ''
  fail=0
  ${lib.concatMapStringsSep "\n" (
    name:
    let
      closure = closureInfo { rootPaths = [ packagesUnderGuard.${name} ]; };
      max = ((budgets.${name} or defaultBudgetMiB) * archFactor) / 100;
    in
    ''
      sizeMiB=$(( $(cat ${closure}/total-nar-size) / 1024 / 1024 ))
      echo "${name}: $sizeMiB MiB (budget ${toString max} MiB)"
      if [ "$sizeMiB" -gt ${toString max} ]; then
        echo "  ^ outgrew its budget"; fail=1
      fi
      ${lib.concatMapStringsSep "\n" (p: ''
        if grep -q -e ${lib.escapeShellArg p} ${closure}/store-paths; then
          echo "  ^ forbidden ${p} crept back in"; fail=1
        fi
      '') (forbidden.${name} or [ ])}
    ''
  ) names}
  [ "$fail" = 0 ] || exit 1
  touch $out
''
