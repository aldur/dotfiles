#!/bin/bash

set -euo pipefail
IFS=$'\n\t'



finish() {
    true
}
trap finish EXIT
