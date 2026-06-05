#!/usr/bin/env python3
"""
Reorganize enUS.lua by grouping each string under the source file that uses it.
Produces `enUS_reorganized.lua` (next to enUS.lua) with one `-- <file>` section
per using-file, plus an UNUSED section. Review and rename it over enUS.lua
manually once you're happy.

This is intentionally generic: sections are derived from real usage, so it works
for any addon without per-addon section rules.

Usage:
    python reorganize_locale.py [ADDON_OR_LOCALES_DIR]

Defaults to the current directory.
"""

import argparse
import os
import re
from collections import OrderedDict, defaultdict

from locale_common import resolve_paths, iter_code_files


def extract_entries(enus):
    """OrderedDict of key -> full source text (handles [[ ]] multi-line values)."""
    entries = OrderedDict()
    with open(enus, "r", encoding="utf-8") as f:
        lines = f.read().split("\n")
    i = 0
    key_re = re.compile(r'''^L\[(["'])((?:\\.|(?!\1).)*)\1\]\s*=\s*(.*)$''')
    while i < len(lines):
        m = key_re.match(lines[i])
        if m:
            key, rest = m.group(2), m.group(3)
            entry = lines[i]
            if rest.strip().startswith("[[") and "]]" not in rest:
                i += 1
                while i < len(lines) and "]]" not in lines[i]:
                    entry += "\n" + lines[i]
                    i += 1
                if i < len(lines):
                    entry += "\n" + lines[i]
            entries[key] = entry
        i += 1
    return entries


def find_primary_file(key, addon_dir):
    pattern = re.compile(r'L\[(["\'])' + re.escape(key) + r'\1\]')
    for path in iter_code_files(addon_dir):
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                if pattern.search(f.read()):
                    return os.path.relpath(path, addon_dir)
        except OSError:
            pass
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?", default=".", help="Addon dir or its Locales dir (default: .)")
    args = ap.parse_args()

    addon_dir, locales_dir, addon_name = resolve_paths(args.path)
    enus = os.path.join(locales_dir, "enUS.lua")
    if not os.path.isfile(enus):
        ap.error(f"enUS.lua not found at {enus}")

    entries = extract_entries(enus)
    print(f"Reorganizing {len(entries)} entries — {addon_name}\n")

    sections = defaultdict(list)
    for i, (key, text) in enumerate(entries.items(), 1):
        if i % 50 == 0:
            print(f"  {i}/{len(entries)}...")
        sections[find_primary_file(key, addon_dir) or "UNUSED"].append((key, text))

    # Stable, readable order: real files alphabetically, UNUSED last.
    ordered = sorted((s for s in sections if s != "UNUSED")) + (["UNUSED"] if "UNUSED" in sections else [])

    out = os.path.join(locales_dir, "enUS_reorganized.lua")
    with open(out, "w", encoding="utf-8") as f:
        f.write(f'local L = LibStub("AceLocale-3.0"):NewLocale("{addon_name}", "enUS", true)\n\n\n')
        for section in ordered:
            f.write(f"-- {section}\n")
            for _, text in sections[section]:
                f.write(text + "\n")
            f.write("\n")

    print(f"\nWritten to {out}")
    for section in ordered:
        print(f"  {section}: {len(sections[section])}")


if __name__ == "__main__":
    main()
