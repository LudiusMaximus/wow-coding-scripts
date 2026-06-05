#!/usr/bin/env python3
"""
Detect duplicate locale keys within each locale file.

Usage:
    python detect_duplicates.py [ADDON_OR_LOCALES_DIR]

Defaults to the current directory.
"""

import argparse
import os
from collections import defaultdict

from locale_common import resolve_paths, locale_files, KEY_DEF_RE, unescape_lua


def duplicates_in(path):
    lines_by_key = defaultdict(list)
    with open(path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            m = KEY_DEF_RE.match(line.strip())
            if m:
                lines_by_key[unescape_lua(m.group(2))].append(line_num)
    return {k: v for k, v in lines_by_key.items() if len(v) > 1}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?", default=".", help="Addon dir or its Locales dir (default: .)")
    args = ap.parse_args()

    _, locales_dir, addon_name = resolve_paths(args.path)
    files = locale_files(locales_dir)
    if not files:
        ap.error(f"No locale .lua files found in {locales_dir}")

    print(f"Duplicate key detection — {addon_name}\n{'=' * 60}")
    total, files_with = 0, 0
    for path in files:
        dups = duplicates_in(path)
        if dups:
            files_with += 1
            print(f"\n{os.path.basename(path)}")
            for key, lines in sorted(dups.items()):
                total += len(lines) - 1
                print(f'  "{key}" x{len(lines)} at lines {", ".join(map(str, lines))}')

    print()
    if files_with == 0:
        print("No duplicate keys found.")
    else:
        print(f"Found {total} duplicate definition(s) across {files_with} file(s).")


if __name__ == "__main__":
    main()
