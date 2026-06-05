#!/usr/bin/env python3
"""
Analyze where each enUS.lua locale string is used across an addon's code.
Helps decide how to group strings when reorganizing the locale file.

Usage:
    python analyze_locale_usage.py [ADDON_OR_LOCALES_DIR] [-o OUTPUT.txt]

ADDON_OR_LOCALES_DIR defaults to the current directory.
"""

import argparse
import os
import re
from collections import defaultdict

from locale_common import resolve_paths, extract_key_defs, iter_code_files


def find_usage(key, addon_dir):
    """Files (relative to addon_dir) that reference L["key"]."""
    pattern = re.compile(r'L\[(["\'])' + re.escape(key) + r'\1\]')
    locations = []
    for path in iter_code_files(addon_dir):
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                if pattern.search(f.read()):
                    locations.append(os.path.relpath(path, addon_dir))
        except OSError as e:
            print(f"Error reading {path}: {e}")
    return locations


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?", default=".", help="Addon dir or its Locales dir (default: .)")
    ap.add_argument("-o", "--output", default="locale_usage_analysis.txt", help="Detailed report file")
    args = ap.parse_args()

    addon_dir, locales_dir, addon_name = resolve_paths(args.path)
    enus = os.path.join(locales_dir, "enUS.lua")
    if not os.path.isfile(enus):
        ap.error(f"enUS.lua not found at {enus}")

    print(f"Analyzing {addon_name} locale usage")
    print(f"  addon:  {addon_dir}")
    print(f"  enUS:   {enus}\n")

    keys = [k for k, _ in extract_key_defs(enus)]
    print(f"Found {len(keys)} locale keys. Searching usage...\n")

    usage = {}
    for i, key in enumerate(keys, 1):
        if i % 50 == 0:
            print(f"  {i}/{len(keys)}...")
        usage[key] = find_usage(key, addon_dir)

    # Group each key under its primary (first) using file; collect unused/multi.
    by_file = defaultdict(list)
    multi = []
    for key, locs in usage.items():
        if not locs:
            by_file["UNUSED"].append(key)
        else:
            by_file[os.path.basename(locs[0])].append(key)
            if len(locs) > 1:
                multi.append(f"{key} -> {', '.join(locs)}")

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(f"{addon_name} Locale String Usage Analysis\n{'=' * 60}\n\n")
        for cat in sorted(by_file):
            f.write(f"\n{cat}  ({len(by_file[cat])})\n{'-' * 60}\n")
            for key in by_file[cat]:
                f.write(f'  L["{key}"]\n')
                for loc in usage[key]:
                    f.write(f"      -> {loc}\n")
        if multi:
            f.write(f"\n\nUSED IN MULTIPLE LOCATIONS\n{'-' * 60}\n")
            for item in multi:
                f.write(f"  {item}\n")

    print(f"\nReport written to {args.output}\nSummary:")
    for cat in sorted(by_file):
        print(f"  {cat}: {len(by_file[cat])}")


if __name__ == "__main__":
    main()
