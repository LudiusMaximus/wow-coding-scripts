#!/usr/bin/env python3
"""
Remove the given locale keys from every locale file (a backup dir is created
first). Intended to consume the output of find_unused_strings.py --keys-only.

Usage:
    python purge_unused_strings.py [ADDON_OR_LOCALES_DIR] --key "Foo" --key "Bar"
    python purge_unused_strings.py [ADDON_OR_LOCALES_DIR] --from-file unused.txt
    python find_unused_strings.py MyAddon --keys-only | \
        python purge_unused_strings.py MyAddon --from-file -

Defaults the path to the current directory. Use --dry-run to preview.
"""

import argparse
import os
import shutil
import sys
from datetime import datetime

from locale_common import resolve_paths, locale_files, KEY_DEF_RE, unescape_lua


def load_keys(args):
    keys = list(args.key or [])
    if args.from_file:
        stream = sys.stdin if args.from_file == "-" else open(args.from_file, "r", encoding="utf-8")
        with stream as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    keys.append(line)
    return set(keys)


def purge_file(path, keys, dry_run):
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    kept, removed = [], 0
    for line in lines:
        m = KEY_DEF_RE.match(line.strip())
        if m and unescape_lua(m.group(2)) in keys:
            removed += 1
            print(f"  - {os.path.basename(path)}: {line.strip()[:70]}")
        else:
            kept.append(line)
    if removed and not dry_run:
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(kept)
    return removed


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?", default=".", help="Addon dir or its Locales dir (default: .)")
    ap.add_argument("--key", action="append", help="A key to remove (repeatable)")
    ap.add_argument("--from-file", help="File (or - for stdin) with one key per line")
    ap.add_argument("--dry-run", action="store_true", help="Show what would be removed; change nothing")
    args = ap.parse_args()

    keys = load_keys(args)
    if not keys:
        ap.error("No keys given. Use --key and/or --from-file.")

    _, locales_dir, addon_name = resolve_paths(args.path)
    files = locale_files(locales_dir)
    if not files:
        ap.error(f"No locale .lua files found in {locales_dir}")

    print(f"Purging {len(keys)} key(s) from {len(files)} locale file(s) — {addon_name}")
    if not args.dry_run:
        backup = os.path.join(locales_dir, f"backup_{datetime.now():%Y%m%d_%H%M%S}")
        os.makedirs(backup, exist_ok=True)
        for path in files:
            shutil.copy2(path, os.path.join(backup, os.path.basename(path)))
        print(f"Backup: {backup}")
    print()

    total = sum(purge_file(p, keys, args.dry_run) for p in files)
    print(f"\n{'Would remove' if args.dry_run else 'Removed'} {total} line(s).")


if __name__ == "__main__":
    main()
