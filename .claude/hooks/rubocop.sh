#!/usr/bin/env bash
# PostToolUse hook: auto-correct the Ruby file Claude just edited so the working
# tree always matches the omakase house style. Remaining offenses are reported
# back so Claude fixes what RuboCop cannot correct automatically.
set -uo pipefail

# Hooks may be invoked from an arbitrary working directory; anchor to the
# project root so the bin/ stubs resolve wherever Claude Code runs us.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0

file=$(jq -r '.tool_input.file_path // empty')
[ -z "$file" ] && exit 0

case "$file" in
  *.rb | *.rake | *.gemspec | *Gemfile | *Rakefile) ;;
  *) exit 0 ;;
esac

if ! output=$(bin/rubocop --autocorrect --force-exclusion "$file" 2>&1); then
  echo "$output" >&2
  exit 2
fi
