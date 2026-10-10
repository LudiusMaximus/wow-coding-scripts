#!/usr/bin/env bash
# Checks that every file an addon loads is actually there.
#
# Usage: check-references.sh <addon folder> [exclude list]
#
# Follows what the game itself follows: every file listed in the folder's .toc
# files, and every <Script file> and <Include file> in the .xml files those reach,
# relative to the file that names them.
#
# A missing file whose path runs through a folder the exclude list leaves out is
# an error, because then it was the packaging that removed something the addon
# needs. Any other missing file is only a warning: it is missing from the source
# too, so the game is already living with it.
#
# Exits 1 if there is an error, 0 otherwise.

set -uo pipefail

root=${1:?usage: check-references.sh <addon folder> [exclude list]}
excludes=${2:-}

# The folder names the exclude list leaves out: its lines ending in a slash.
excluded_dirs=()
if [ -n "$excludes" ] && [ -f "$excludes" ]; then
  while IFS= read -r pattern; do
    pattern=${pattern%$'\r'}
    case "$pattern" in
      ''|'#'*|';'*) continue ;;
      */) excluded_dirs+=("${pattern%/}") ;;
    esac
  done < "$excludes"
fi

# Whether a path runs through one of the excluded folders.
through_excluded() {
  local path=$1 part dir
  local IFS=/
  for part in $path; do
    for dir in "${excluded_dirs[@]+"${excluded_dirs[@]}"}"; do
      [ "$part" = "$dir" ] && { echo "$dir"; return 0; }
    done
  done
  return 1
}

errors=0
warnings=0
queue=()
declare -A seen=()

# The .toc files list paths with backslashes, one per line, after any ## lines,
# and may end a line with a clause such as [AllowLoadGameType mists, tbc].
for toc in "$root"/*.toc; do
  [ -f "$toc" ] || continue
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    line=${line#$'\xef\xbb\xbf'}
    case "$line" in
      ''|'#'*) continue ;;
    esac
    line=${line%%[[:space:]]\[*}
    line=${line%"${line##*[![:space:]]}"}
    line=${line//\\//}
    queue+=("$line")
  done < "$toc"
done

while [ ${#queue[@]} -gt 0 ]; do
  file=${queue[0]}
  queue=("${queue[@]:1}")

  # Resolve ".." and "." so that two spellings of one file are seen once.
  normalised=$(cd "$root" && realpath -m --relative-to=. "$file" 2>/dev/null || echo "$file")
  [ -n "${seen[$normalised]+x}" ] && continue
  seen[$normalised]=1

  if [ ! -f "$root/$normalised" ]; then
    if dir=$(through_excluded "$normalised"); then
      echo "ERROR:   $normalised is loaded, but the excluded folder \"$dir/\" removed it" >&2
      errors=$((errors + 1))
    else
      echo "warning: $normalised is loaded, but missing" >&2
      warnings=$((warnings + 1))
    fi
    continue
  fi

  case "$normalised" in
    *.xml|*.XML)
      base=$(dirname "$normalised")
      while IFS= read -r ref; do
        ref=${ref//\\//}
        if [ "$base" = "." ]; then queue+=("$ref"); else queue+=("$base/$ref"); fi
      # A reference inside an XML comment is not loaded. Comments may run over
      # several lines and contain ">", hence perl rather than a line based tool.
      done < <(perl -0777 -pe 's/<!--.*?-->//gs; s/\r//g' "$root/$normalised" \
               | grep -oE '<(Script|Include)[^>]*file="[^"]+"' \
               | sed -E 's/.*file="([^"]+)".*/\1/')
      ;;
  esac
done

if [ "$errors" -gt 0 ]; then
  echo "$errors file(s) the addon loads were left out by the exclude list." >&2
  exit 1
fi
exit 0
