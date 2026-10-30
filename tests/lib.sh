#!/bin/bash
# Shared test helpers; sourced by tests/run.sh.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034 # used by the sourced test files
FIXTURES="$ROOT/tests/fixtures"

assert_eq() {
  if [[ "$1" != "$2" ]]; then
    printf '    %s\n    expected: %q\n    actual:   %q\n' "$3" "$1" "$2" >&2
    return 1
  fi
}

assert_contains() {
  if [[ "$2" != *"$1"* ]]; then
    printf '    %s\n    expected to contain: %q\n    actual: %q\n' "$3" "$1" "$2" >&2
    return 1
  fi
}
