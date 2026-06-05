#!/usr/bin/env python3
"""
Find locale strings defined in enUS.lua but never referenced in the addon's
code (.lua and .xml, excluding Locales/ and Libs/).

Usage:
    python find_unused_strings.py [ADDON_OR_LOCALES_DIR] [--keys-only]

--keys-only prints just the unused keys (one per line), suitable for piping
into purge_unused_strings.py --from-file -.

Defaults to the current directory.
"""

import argparse
import os
import sys

from locale_common import resolve_paths, extract_key_defs, iter_code_files


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?", default=".", help="Addon dir or its Locales dir (default: .)")
    ap.add_argument("--keys-only", action="store_true", help="Print only the unused keys, one per line")
    args = ap.parse_args()

    addon_dir, locales_dir, addon_name = resolve_paths(args.path)
    enus = os.path.join(locales_dir, "enUS.lua")
    if not os.path.isfile(enus):
        ap.error(f"enUS.lua not found at {enus}")

    # Read every code file once.
    blobs = []
    for path in iter_code_files(addon_dir):
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                blobs.append((os.path.relpath(path, addon_dir), f.read()))
        except OSError:
            pass

    keys = extract_key_defs(enus)

    def usages(key):
        # Match the key as L["key"] / L['key'] in any code file.
        needles = (f'L["{key}"]', f"L['{key}']")
        return [name for name, content in blobs if any(n in content for n in needles)]

    unused, used = [], 0
    for key, line in keys:
        if usages(key):
            used += 1
        else:
            unused.append((key, line))

    if args.keys_only:
        for key, _ in unused:
            print(key)
        return

    print(f"Unused locale strings — {addon_name}\n{'=' * 60}")
    print(f"Code files scanned: {len(blobs)}   Keys: {len(keys)}   "
          f"Used: {used}   Unused: {len(unused)}\n")
    if unused:
        for key, line in unused:
            print(f"  line {line:4d}: \"{key}\"")
        print("\nNote: a 'key' may be a false positive if it is built dynamically "
              "at runtime. Review before purging.")
    else:
        print("All locale keys are referenced.")


if __name__ == "__main__":
    main()
