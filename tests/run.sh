#!/bin/bash
# Minimal runner: each tests/*.test.sh defines test_* functions, each run in its own subshell.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tests/lib.sh
source tests/lib.sh

pass=0
fail=0
for file in tests/*.test.sh; do
  [[ -n "${1:-}" && "$file" != *"$1"* ]] && continue
  # shellcheck disable=SC1090
  source "$file"
  for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    # Not run as an `if` condition: that context silently disables set -e inside the test.
    (set -e; TEST_TMP="$(mktemp -d)"; export TEST_TMP; trap 'rc=$?; rm -rf "$TEST_TMP"; exit $rc' EXIT; "$t")
    rc=$?
    if [[ $rc -eq 0 ]]; then
      printf 'PASS %s\n' "$t"; pass=$((pass + 1))
    else
      printf 'FAIL %s\n' "$t"; fail=$((fail + 1))
    fi
    unset -f "$t"
  done
done
printf '%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
