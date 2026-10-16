#!/usr/bin/env bash
# Checks that no development code is switched on in a release.
#
# Usage: check-dev-code.sh <repository>
#
# Two markers are recognised in the repository's tracked .lua, .xml and .toc files:
#
#   --@debug@             Code for development only, such as opening the options
#   ...                   after every reload. The first line is the switch: as
#   --@end-debug@]===]    written here the block runs, which refuses the release.
#                         To switch it off, open it with --[===[@debug@ instead,
#                         which makes the whole block a comment up to the ]===] of
#                         the last line. (That is also the form the BigWigs
#                         packager gives these blocks in its zips.)
#                         Lua files only. Each marker goes on a line of its own,
#                         and blocks do not nest.
#
#   @no-release@          Anywhere in a line, commented out or not: a reminder
#                         that something has to be undone before the next release.
#                         As long as it is there, the release is refused.
#
# A debug marker spelt slightly differently, such as "-- @debug@", would let its
# code run unnoticed, so anything that looks like a debug marker without being
# exactly one is an error too.
#
# The working tree is checked, which is what release.sh packs.
#
# Exits 1 if there is an error, 0 otherwise.

set -uo pipefail

repo=${1:?usage: check-dev-code.sh <repository>}
cd "$repo" || exit 1

# Without git, there would be no files to check, and so nothing to refuse.
git rev-parse --is-inside-work-tree >/dev/null || { echo "check-dev-code: not a git repository: $repo" >&2; exit 1; }

errors=0

while IFS= read -r -d '' file; do
  # Tracked, but deleted in the working tree.
  [ -f "$file" ] || continue

  case "$file" in
    *.lua) lua=1 ;;
    *)     lua=0 ;;
  esac

  # One line per problem; the exit status is the number of problems (capped).
  awk -v file="$file" -v lua="$lua" '
    function problem(msg, line) {
      printf "ERROR:   %s:%d: %s\n", file, (line ? line : NR), msg
      count++
    }

    function opening() {
      if (open) problem("debug block inside the block opened in line " open)
      else open = NR
    }

    { sub(/\r$/, "") }

    /@no-release@/ {
      problem("@no-release@ marker")
    }

    /@(end-)?debug@/ {
      if (!lua) {
        problem("debug markers are only supported in .lua files")
      } else if ($0 ~ /^[ \t]*--@debug@[ \t]*$/) {
        problem("debug block is switched on")
        opening()
      } else if ($0 ~ /^[ \t]*--\[===\[@debug@[ \t]*$/) {
        opening()
      } else if ($0 ~ /^[ \t]*--@end-debug@\]===\][ \t]*$/) {
        if (!open) problem("end of a debug block that was never opened")
        open = 0
      } else {
        problem("debug marker not on a line of its own, or misspelt: " $0)
      }
      next
    }

    # A switched off block is a --[===[ ]===] comment, which this would end early.
    open && /\]===\]/ {
      problem("]===] inside a debug block")
    }

    END {
      if (open) problem("debug block is never closed", open)
      exit (count > 100 ? 100 : count)
    }
  ' "$file" >&2
  errors=$((errors + $?))

done < <(git ls-files -z -- '*.lua' '*.xml' '*.toc')

if [ "$errors" -gt 0 ]; then
  echo "$errors problem(s) with development code markers." >&2
  exit 1
fi
exit 0
