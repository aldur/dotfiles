#!/bin/bash
set -euo pipefail

dir="/tmp/vim-anywhere"
mkdir -p $dir
file=$(mktemp -p $dir)

vimr -s --wait "${file}"
pbcopy < "${file}"
