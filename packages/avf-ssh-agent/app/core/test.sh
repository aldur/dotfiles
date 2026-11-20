#!/usr/bin/env bash
# Compiles the core and its tests with plain javac and runs the tests. Needs a JDK 17 or later.
set -euo pipefail
cd "$(dirname "$0")"
classes=$(mktemp -d)
trap 'rm -rf "$classes"' EXIT
find src -name '*.java' -print0 | xargs -0 javac --release 17 -Xlint:all -Werror -d "$classes"
java -ea -cp "$classes" io.github.aldur.avfsshagent.core.AllTests
