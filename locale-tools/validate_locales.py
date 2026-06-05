#!/usr/bin/env python3
"""
Validate that every locale file defines the same keys as enUS.lua (the source
of truth). Reports keys missing from each translation, and any extra keys not
present in enUS.

Usage:
    python validate_locales.py [ADDON_OR_LOCALES_DIR] [--show-extra]

Defaults to the current directory. Exit code is non-zero if anything is missing.
"""

import argparse
import os
import sys

from locale_common import resolve_paths, locale_files, extract_key_defs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?", default=".", help="Addon dir or its Locales dir (default: .)")
    ap.add_argument("--show-extra", action="store_true", help="Also report keys not present in enUS.lua")
    args = ap.parse_args()

    _, locales_dir, addon_name = resolve_paths(args.path)
    enus = os.path.join(locales_dir, "enUS.lua")
    if not os.path.isfile(enus):
        ap.error(f"enUS.lua not found at {enus}")

    required = {k for k, _ in extract_key_defs(enus)}
    print(f"Validating locales against enUS.lua ({len(required)} keys) — {addon_name}\n")

    incomplete = False
    for path in locale_files(locales_dir):
        if os.path.basename(path) == "enUS.lua":
            continue
        defined = {k for k, _ in extract_key_defs(path)}
        missing = required - defined
        extra = defined - required
        name = os.path.basename(path)
        if not missing and not (args.show_extra and extra):
            print(f"OK   {name}")
            continue
        if missing:
            incomplete = True
            print(f"MISS {name}: {len(missing)} missing")
            for key in sorted(missing):
                print(f"       - {key}")
        if args.show_extra and extra:
            print(f"XTRA {name}: {len(extra)} not in enUS")
            for key in sorted(extra):
                print(f"       + {key}")

    sys.exit(1 if incomplete else 0)


if __name__ == "__main__":
    main()
