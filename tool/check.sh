#!/usr/bin/env bash
#
# Runs exactly the gates CI runs, in the same order, and reports all of them.
#
# This exists because running the gates ad-hoc is how a failing format check
# reached main: analyze and test were run by hand, the format check was not, and
# nothing made that omission visible.
#
# Usage: tool/check.sh
#
set -uo pipefail

# Regenerated code is not committed, so it has to exist before analyze or test.
echo "==> generating code"
dart run build_runner build --delete-conflicting-outputs >/dev/null 2>&1
flutter gen-l10n >/dev/null 2>&1

failures=0

run() {
  local name="$1"; shift
  printf '\n==> %s\n' "$name"
  if "$@"; then
    printf '    PASS: %s\n' "$name"
  else
    printf '    FAIL: %s\n' "$name"
    failures=$((failures + 1))
  fi
}

run "format"  dart format --output=none --set-exit-if-changed .
run "analyze" flutter analyze
run "test"    flutter test

printf '\n'
if [ "$failures" -eq 0 ]; then
  echo "All gates passed."
else
  echo "$failures gate(s) failed."
fi
exit "$failures"
