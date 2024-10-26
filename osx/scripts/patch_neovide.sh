#!/usr/bin/env bash

# shellcheck disable=SC2016
if test "$BASH" = "" || "$BASH" -uc 'a=();true "${a[@]}"' 2>/dev/null; then
	# Bash 4.4, Zsh
	set -Eeuo pipefail
else
	# Bash 4.3 and older chokes on empty arrays with set -u.
	set -Eeo pipefail
fi
if shopt | grep globstar; then
	shopt -s nullglob globstar || true
fi

set -x

# Magic script to get this script's directory.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

NEOVIDE_APP="/Applications/Nix Apps/Neovide.app"
if test ! -e "$NEOVIDE_APP"; then
	NEOVIDE_APP="/Applications/Neovide.app"
	if test ! -e "$NEOVIDE_APP"; then
		echo "Can't find Neovide.app!"
		exit 1
	fi
fi

NEOVIDE_PLIST="$NEOVIDE_APP"/Contents/Info.plist
NEOVIDE_EXECUTABLE="$NEOVIDE_APP"/Contents/MacOS/neovide
NEOVIDE_SERVER="$NEOVIDE_EXECUTABLE"_server.sh

if test ! -f "$NEOVIDE_PLIST"; then
	echo "Can't find Neovide's plist!"
	exit 1
fi

NVIM_SOCKET=/tmp/neovide.socket
NVIM_BINARY=/Users/aldur/.dotfiles/neovim/result/bin/nvim

cat <<EOF >"$NEOVIDE_SERVER"
#!/bin/sh

NVIM_SOCKET=$NVIM_SOCKET
if [ ! -S \$NVIM_SOCKET ]; then
    "$NEOVIDE_EXECUTABLE" --frame=transparent --no-tabs --title-hidden --neovim-bin "$NVIM_BINARY" -- --listen \$NVIM_SOCKET --cmd "cd ~" "\$@"
else
    "$NVIM_BINARY" --server \$NVIM_SOCKET --remote "\$(grealpath -m "\$@" | tr '\n' ' ' | sed 's/ $/\n/')"
    open -a Neovide  # Ensures front
fi
EOF

chmod +x "$NEOVIDE_SERVER"

# If '`neovide` is on PATH, we replace it with patched version
if NEOVIDE_PATH=$(which neovide); then
	if test -L "$NEOVIDE_PATH"; then
		ln -sf "$NEOVIDE_SERVER" "$NEOVIDE_PATH"
	fi
fi

cp "$NEOVIDE_PLIST" "$NEOVIDE_PLIST.back"
# https://www.marcosantadev.com/manage-plist-files-plistbuddy/
/usr/libexec/PlistBuddy -c "Set CFBundleExecutable $(basename "$NEOVIDE_SERVER")" "$NEOVIDE_PLIST"

cp "$SCRIPT_DIR"/neovide.icns "$NEOVIDE_APP/Contents/Resources/neovide.icns"

# https://superuser.com/questions/271678/how-do-i-pass-command-line-arguments-to-dock-items
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$NEOVIDE_APP"
