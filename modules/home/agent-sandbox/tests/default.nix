{ pkgs, lib }:
let
  mkWrapper = import ../package.nix { inherit pkgs lib; };
  wrapper = mkWrapper {
    profiles = lib.genAttrs [ "claude" "codex" ] (name: {
      runtimeAllowlist = [ "allowed" ];
      extraDbusTalk = [ "org.example.Allowed" ];
      readOnlyPaths = [ "~/Reference notes" ];
      readWritePaths = [ "~/Shared code" ];
      stateKind = name;
      agentReadOnlyPaths = [ "~/.${name}/bin" ];
      extraEnvironmentAllowlist = [ "PROFILE_VALUE" ];
      allowNixDaemon = name == "codex";
    });
  };

  seccompProbe = pkgs.runCommandCC "agent-seccomp-probe" { } ''
    $CC -Wall -Wextra -Werror ${./seccomp.c} -o "$out"
  '';
  unavailableSeccomp =
    pkgs.runCommandCC "unavailable-seccomp.bpf"
      {
        buildInputs = [ pkgs.libseccomp ];
      }
      ''
        $CC -Wall -Wextra -Werror ${./unavailable-seccomp.c} -lseccomp -o generate-filter
        ./generate-filter > "$out"
      '';

  securityProbe = pkgs.replaceVars ./isolation.py {
    inherit seccompProbe;
    gpg = "${pkgs.gnupg}/bin/gpg";
    bwrap = "${pkgs.bubblewrap}/bin/bwrap";
    bash = "${pkgs.bash}/bin/bash";
  };

  probe = pkgs.writeShellScript "agent-sandbox-probe" ''
    set -euo pipefail
    test "$(id -u)" -ne 0
    test -z "''${SSH_AUTH_SOCK:-}"
    test ! -e "$HOME/.ssh/secret"
    test ! -e /persist/home/tester/.ssh/secret
    test ! -e /persist/home/tester/.local/share/fish/fish_history
    test ! -e /persist/home/tester/.config/fish/config.fish
    test ! -e /persist/system-state
    test ! -e /tmp/ssh-advertised/agent
    test ! -e /tmp/ssh-unadvertised/agent
    test ! -e "/tmp/tmux-$(id -u)/default"
    test ! -e "$XDG_RUNTIME_DIR/agent"
    test ! -e /tmp/host-marker
    test ! -e "$HOME/.local/share/fish/fish_history"
    test ! -e "$HOME/Unrelated/secret"
    test ! -e "$HOME/Work/outside/secret"
    test ! -e /etc/unrelated-secret
    test ! -e /var/lib/unrelated/secret
    test ! -e /nix/var/nix/unrelated-secret
    test "$(cat "$HOME/Reference notes/marker")" = reference
    if (echo changed > "$HOME/Reference notes/marker") 2>/dev/null; then
      echo 'configured reference path must stay read-only' >&2
      exit 1
    fi
    echo edited > "$HOME/Shared code/result"
    test "$(cat "$HOME/Extra reference/marker")" = reference
    echo edited > "$HOME/Extra output/result"
    test "$(cat "$HOME/Work/locked/marker")" = locked
    if (echo changed > "$HOME/Work/locked/marker") 2>/dev/null; then
      echo 'read-only mount must override the writable grant' >&2
      exit 1
    fi
    mkdir -p "$HOME/.$TEST_AGENT/sessions"
    echo session > "$HOME/.$TEST_AGENT/sessions/probe-session"
    if [ "$TEST_AGENT" = claude ]; then
      grep -q '"fixture":true' "$HOME/.claude.json"
    fi
    "$HOME/.$TEST_AGENT/bin/tool"
    if (echo changed > "$HOME/.$TEST_AGENT/bin/tool") 2>/dev/null; then
      echo 'agent installation must stay read-only' >&2
      exit 1
    fi
    test "$(cat "$HOME/.config/fish/config.fish")" = config
    if (echo changed > "$HOME/.config/fish/config.fish") 2>/dev/null; then
      echo 'preserved fish configuration must stay read-only' >&2
      exit 1
    fi
    test "$(cat "$XDG_RUNTIME_DIR/allowed/marker")" = allowed
    test "$TMPDIR" = /tmp
    mktemp > /dev/null
    echo private > /tmp/host-marker
    echo private > "$HOME/.bashrc"
    echo edited > "$HOME/Work/result"
    ${pkgs.dbus}/bin/dbus-send --session --print-reply \
      --dest=org.freedesktop.DBus /org/freedesktop/DBus \
      org.freedesktop.DBus.ListNames > /dev/null
    ${pkgs.python3}/bin/python3 ${securityProbe}
  '';

  # Run only against synthetic files and sockets in an outer namespace.
  # The real wrapper must also work when SSH_AUTH_SOCK was already unset.
  fixtureRunner = pkgs.replaceVars ./integration.py {
    inherit probe seccompProbe unavailableSeccomp;
    python = "${pkgs.python3}/bin/python3";
    bash = "${pkgs.bash}/bin/bash";
    bwrap = "${pkgs.bubblewrap}/bin/bwrap";
    dbusTestTool = "${pkgs.dbus}/bin/dbus-test-tool";
    dbusSend = "${pkgs.dbus}/bin/dbus-send";
    metadataTests = pkgs.replaceVars ./metadata.py {
      git = "${pkgs.git}/bin/git";
    };
    direnvTests = pkgs.replaceVars ./direnv.py {
      direnv = lib.getExe pkgs.direnv;
      git = lib.getExe pkgs.git;
      bash = "${pkgs.bash}/bin/bash";
      stdlib = pkgs.writeText "direnvrc" (
        import ../../../shared/programs/direnv/stdlib.nix { inherit pkgs; }
      );
    };
  };
in
pkgs.runCommand "agent-sandbox-test"
  {
    nativeBuildInputs = [
      pkgs.bubblewrap
      pkgs.coreutils
      pkgs.dbus
      pkgs.python3
    ];
  }
  ''
    fixture=$PWD/fixture
    user_state=$fixture/persist/home/tester
    mkdir -p "$fixture/home/.local/share/direnv"
    mkdir -p "$fixture/home" "$user_state/.ssh" "$user_state/Work" \
      "$user_state/.local/share/fish" "$user_state/.config/fish"
    for dir in 'Reference notes' 'Extra reference' 'Shared code' 'Extra output' 'Other workspace' Unrelated; do
      mkdir -p "$fixture/home/$dir"
    done
    for agent in claude codex; do
      mkdir -p "$fixture/home/.$agent/bin"
      echo fixture-auth > "$fixture/home/.$agent/auth"
      printf '#!${pkgs.bash}/bin/bash\nexit 0\n' > "$fixture/home/.$agent/bin/tool"
      chmod +x "$fixture/home/.$agent/bin/tool"
    done
    echo '{"token":"fixture"}' > "$fixture/home/.codex/auth.json"
    echo '{"token":"fixture"}' > "$fixture/home/.claude/.credentials.json"
    echo 'model = "fixture"' > "$fixture/home/.codex/config.toml"
    echo '{}' > "$fixture/home/.claude/settings.json"
    echo '{"mcpServers":{},"fixture":true}' > "$fixture/home/.claude.json"
    echo reference > "$fixture/home/Reference notes/marker"
    echo reference > "$fixture/home/Extra reference/marker"
    echo unrelated > "$fixture/home/Unrelated/secret"
    mkdir -p "$user_state/Work/locked"
    echo locked > "$user_state/Work/locked/marker"
    ln -s /home/tester/Unrelated "$user_state/Work/outside"
    ln -s / "$fixture/home/root-link"
    echo secret > "$user_state/.ssh/secret"
    mkdir -p "$fixture/home/.gnupg/private-keys-v1.d" "$fixture/home/Custom GPG"
    echo private-key-fixture > "$fixture/home/.gnupg/private-keys-v1.d/secret.key"
    echo custom-key-fixture > "$fixture/home/Custom GPG/secret.key"
    echo history > "$user_state/.local/share/fish/fish_history"
    echo config > "$user_state/.config/fish/config.fish"
    echo system > "$fixture/persist/system-state"
    uid=$(id -u)
    echo "tester:x:$uid:$(id -g)::/home/tester:${pkgs.bash}/bin/bash" > "$fixture/passwd"

    # writeArgcApplication installs completions from the same option annotations.
    test -s ${wrapper}/share/bash-completion/completions/agent-sandbox.bash
    test -s ${wrapper}/share/zsh/site-functions/_agent-sandbox
    test -s ${wrapper}/share/fish/vendor_completions.d/agent-sandbox.fish

    for persistence in present absent; do
      args=(
        --unshare-pid
        --tmpfs /
        --ro-bind /nix/store /nix/store
        --ro-bind "$fixture/home/Unrelated/secret" /nix/var/nix/unrelated-secret
        --ro-bind "$fixture/passwd" /etc/passwd
        --ro-bind "$fixture/home/Unrelated/secret" /etc/unrelated-secret
        --ro-bind "$fixture/home/Unrelated/secret" /etc/static/unrelated-secret
        --ro-bind ${pkgs.cacert}/etc/ssl/certs /etc/static/ssl/certs
        --symlink /etc/static/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt
        --symlink /etc/static/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
        --ro-bind "$fixture/home/Unrelated" /var/lib/unrelated
        --dev /dev
        --ro-bind "$fixture/home/Unrelated/secret" /dev/host-device
        --proc /proc
        --tmpfs /tmp
        --dir "/run/user/$uid"
        --bind "$fixture/home" /home/tester
        --bind "$user_state/.ssh" /home/tester/.ssh
        --bind "$user_state/Work" /home/tester/Work
        --bind "$user_state/.local/share/fish" /home/tester/.local/share/fish
        --bind "$user_state/.config/fish" /home/tester/.config/fish
        --setenv HOME /home/tester
        --setenv XDG_RUNTIME_DIR "/run/user/$uid"
        --unsetenv XDG_DATA_HOME
        --chdir /home/tester/Work
      )
      if [ "$persistence" = present ]; then
        args+=(--bind "$fixture/persist" /persist)
        args+=(--bind "$fixture/home/.codex" /persist/home/tester/.codex)
        args+=(--bind "$fixture/home/.local/share/direnv" /persist/home/tester/.local/share/direnv)
      fi
      bwrap "''${args[@]}" -- dbus-run-session \
        --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- \
        python3 ${fixtureRunner} ${lib.getExe wrapper}
    done
    touch "$out"
  ''
