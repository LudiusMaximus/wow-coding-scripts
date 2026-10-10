#!/usr/bin/env bash
# Checks that a library raises its LibStub MINOR whenever its code changes.
#
# Usage: check-minor.sh <repository> [release]
#
# LibStub keeps one copy of a library per MAJOR and lets the highest MINOR win, so
# two releases with different code but the same MINOR cannot be told apart: which
# one players get then depends on which addon happens to load first.
#
# Every tracked .lua file that calls LibStub:NewLibrary is compared against the
# previous release tag. Addons are left alone without needing to be told, because
# the libraries they embed sit in ignored folders and are not tracked files.
#
# [release] is a commit or tag to check as if it were being released. Without it,
# the working tree is checked, which is what release.sh packs.
#
#   code changed, MINOR the same     error
#   MINOR lower than before          error
#   MAJOR changed                    warning: to LibStub that is a new library,
#                                    which is right for a breaking change only
#
# Exits 1 if there is an error, 0 otherwise.

set -uo pipefail

repo=${1:?usage: check-minor.sh <repository> [release]}
release=${2:-}
cd "$repo" || exit 1

# The commit being released, and the newest tag before it. Tags on the commit
# itself are this release's own, so the search starts at its parent.
#
# Uncommitted changes are different: they sit on top of the commit, so for a file
# that has them, a tag on the commit itself is already the previous release.
commit=$(git rev-parse --verify -q "${release:-HEAD}^{commit}") || { echo "check-minor: no such commit: ${release:-HEAD}" >&2; exit 1; }
tag_before_commit=$(git describe --tags --abbrev=0 "$commit^" 2>/dev/null || true)
tag_at_commit=$(git describe --tags --abbrev=0 "$commit" 2>/dev/null || true)

# Prints "MAJOR MINOR" for a library file read from stdin, or nothing.
parse() {
  local src major minor
  src=$(tr -d '\r')
  # local MAJOR, MINOR = "LibFoo-1.0", 3   (also ACEDB_MINOR and the like)
  read -r major minor < <(printf '%s\n' "$src" \
    | grep -m1 -oE '[A-Z_]*MAJOR, *[A-Z_]*MINOR *= *"[^"]+", *[0-9]+' \
    | sed -E 's/.*= *"([^"]+)", *([0-9]+)/\1 \2/')
  # local MAJOR = "LibFoo-1.0" and local MINOR = 3 on lines of their own
  if [ -z "${minor:-}" ]; then
    major=$(printf '%s\n' "$src" | grep -m1 -oE '[A-Z_]*MAJOR *= *"[^"]+"' | sed -E 's/.*"([^"]+)"/\1/')
    minor=$(printf '%s\n' "$src" | grep -m1 -oE '[A-Z_]*MINOR *= *[0-9]+' | grep -oE '[0-9]+$')
  fi
  [ -n "${major:-}" ] && [ -n "${minor:-}" ] && echo "$major $minor"
}

content_now() {
  if [ -n "$release" ]; then git show "$commit:$1" 2>/dev/null; else cat "$1"; fi
}

errors=0
while IFS= read -r file; do
  now=$(content_now "$file") || continue
  printf '%s\n' "$now" | grep -q 'LibStub:NewLibrary' || continue

  previous=$tag_before_commit
  if [ -z "$release" ] && \
     [ "$(printf '%s\n' "$now" | tr -d '\r')" != "$(git show "$commit:$file" 2>/dev/null | tr -d '\r')" ]; then
    previous=$tag_at_commit
  fi
  [ -n "$previous" ] || continue                                  # no earlier tag: first release

  before=$(git show "$previous:$file" 2>/dev/null) || continue   # new since the last release

  read -r major_now minor_now < <(printf '%s\n' "$now" | parse)
  read -r major_before minor_before < <(printf '%s\n' "$before" | parse)
  if [ -z "${minor_now:-}" ] || [ -z "${minor_before:-}" ]; then
    echo "warning: $file: could not read MAJOR and MINOR, so it was not checked" >&2
    continue
  fi

  if [ "$major_now" != "$major_before" ]; then
    echo "warning: $file: MAJOR changed from \"$major_before\" to \"$major_now\" since $previous." >&2
    echo "         To LibStub that is a new library, loaded beside the old one. Right for a" >&2
    echo "         breaking change only; every LibStub(\"$major_before\") call now needs updating." >&2
    continue
  fi

  if [ "$minor_now" -lt "$minor_before" ]; then
    echo "ERROR:   $file: MINOR went down from $minor_before to $minor_now since $previous." >&2
    echo "         LibStub would keep any older copy over this one." >&2
    errors=$((errors + 1))
    continue
  fi

  if [ "$minor_now" -eq "$minor_before" ] && \
     [ "$(printf '%s\n' "$now" | tr -d '\r')" != "$(printf '%s\n' "$before" | tr -d '\r')" ]; then
    echo "ERROR:   $file changed since $previous, but MINOR is still $minor_now." >&2
    echo "         Raise it, or LibStub cannot tell this release's code from $previous's." >&2
    errors=$((errors + 1))
  fi
done < <(git ls-files '*.lua')

[ "$errors" -eq 0 ]
