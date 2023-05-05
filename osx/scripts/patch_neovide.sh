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

NEOVIDE_APP=/Applications/Neovide.app
NEOVIDE_PLIST=$NEOVIDE_APP/Contents/Info.plist
NEOVIDE_EXECUTABLE=$NEOVIDE_APP/Contents/MacOS/neovide
NEOVIDE_SERVER="$NEOVIDE_EXECUTABLE"_server.sh

if test ! -f $NEOVIDE_PLIST; then
	echo "Can't find Neovide's plist!"
	exit 1
fi

# Ensure's homebrew's PATH
PATH=/opt/homebrew/bin:$PATH
# Needed for `readlink`
PATH=/opt/homebrew/opt/coreutils/libexec/gnubin/readlink:$PATH

if ! NEOVIDE_PATH=$(which neovide); then
	echo "Can't find Neovide's executable on PATH!"
	exit 1
fi

if ! test -L "$NEOVIDE_PATH"; then
	echo "Neovide on PATH is not a symlink!"
	exit 1
fi

NVIM_SOCKET=/tmp/neovide.socket

cat <<EOF >$NEOVIDE_SERVER
#!/bin/sh

NVIM_SOCKET=$NVIM_SOCKET
if [ ! -S \$NVIM_SOCKET ]; then
    $NEOVIDE_EXECUTABLE --noidle -- --listen \$NVIM_SOCKET +"cd ~" "\$@"
else
    nvim --server \$NVIM_SOCKET --remote "\$(readlink -f "\$@" | tr '\n' ' ' | sed 's/ $/\n/')"
    open -a Neovide  # Ensures front
fi
EOF

chmod +x $NEOVIDE_SERVER

ln -sf $NEOVIDE_SERVER "$NEOVIDE_PATH"

cp $NEOVIDE_PLIST $NEOVIDE_PLIST.back
# https://www.marcosantadev.com/manage-plist-files-plistbuddy/
/usr/libexec/PlistBuddy -c "Set CFBundleExecutable $(basename $NEOVIDE_SERVER)" $NEOVIDE_PLIST

# https://superuser.com/questions/271678/how-do-i-pass-command-line-arguments-to-dock-items
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $NEOVIDE_APP
