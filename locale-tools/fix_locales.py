#!/usr/bin/env python3
"""
Bulk find-and-replace across all locale files (e.g. after renaming a key).

Usage:
    python fix_locales.py [ADDON_OR_LOCALES_DIR] \
        --replace 'L["Old Key"]' 'L["New Key"]' \
        --replace 'L["Another Old"]' 'L["Another New"]'

--replace OLD NEW may be repeated. Use --dry-run to preview.
Defaults the path to the current directory.
"""

import argparse
import os

from locale_common import resolve_paths, locale_files


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?", default=".", help="Addon dir or its Locales dir (default: .)")
    ap.add_argument("--replace", nargs=2, action="append", metavar=("OLD", "NEW"),
                    help="A literal find/replace pair (repeatable)")
    ap.add_argument("--dry-run", action="store_true", help="Report changes without writing")
    args = ap.parse_args()

    if not args.replace:
        ap.error("No replacements given. Use --replace OLD NEW (repeatable).")

    _, locales_dir, addon_name = resolve_paths(args.path)
    files = locale_files(locales_dir)
    if not files:
        ap.error(f"No locale .lua files found in {locales_dir}")

    print(f"Applying {len(args.replace)} replacement(s) to {len(files)} file(s) — {addon_name}\n")
    changed = 0
    for path in files:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        new = content
        for old, repl in args.replace:
            new = new.replace(old, repl)
        if new != content:
            changed += 1
            print(f"  {'would update' if args.dry_run else 'updated'} {os.path.basename(path)}")
            if not args.dry_run:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(new)

    print(f"\n{changed} file(s) {'would change' if args.dry_run else 'changed'}.")


if __name__ == "__main__":
    main()
