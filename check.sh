#!/bin/sh
set -eu

cd "$(dirname "$0")"

BEND_BIN=${BEND_BIN:-bend}

"$BEND_BIN" main.bend
"$BEND_BIN" PROOF.bend
"$BEND_BIN" tests/main.bend
"$BEND_BIN" tests/json_test_suite.bend
