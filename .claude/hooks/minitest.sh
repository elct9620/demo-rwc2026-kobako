#!/usr/bin/env bash
# Stop hook: run the test suite before Claude finishes a turn. Failures block
# stopping and are handed back, so they get fixed in the same session.
set -uo pipefail

# Hooks may be invoked from an arbitrary working directory; anchor to the
# project root so the bin/ stubs resolve wherever Claude Code runs us.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0

# Don't loop: when we already blocked once, let Claude stop after it responds.
if [ "$(jq -r '.stop_hook_active // false')" = "true" ]; then
  exit 0
fi

if ! output=$(bin/rails test 2>&1); then
  echo "$output" >&2
  echo "Minitest failed — fix the failing tests before finishing." >&2
  exit 2
fi
