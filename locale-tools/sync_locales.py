#!/usr/bin/env python3
"""
Sync locale files to enUS.lua's structure.

For every target language, rewrites `<lang>.lua` so it mirrors enUS.lua exactly
(same key order, comments, blank lines and "..." vs [[ ]] value shape), while:
  - PRESERVING any translation that language already has for a key, and
  - falling back to the English value for keys it doesn't translate yet.

This keeps every locale file a structural twin of enUS.lua, so new strings show
up everywhere (as English placeholders) and diffs stay clean. It carries NO
hardcoded translations — it only moves existing strings around.

(Generic successor to the old addon-specific sync script: that one additionally
baked in a per-addon dictionary of hand translations. Maintain translations in
the locale files themselves; this tool just keeps them in sync.)

Usage:
    python sync_locales.py [ADDON_OR_LOCALES_DIR] [--lang deDE --lang frFR ...]

Target languages default to the `<lang>.lua` files already present (minus
enUS). If none exist, the standard WoW locale set is created. Backups are
written to a timestamped folder. Use --dry-run to preview which files change.
"""

import argparse
import os
import re
import shutil
from datetime import datetime

from locale_common import resolve_paths, escape_lua, unescape_lua

STANDARD_LANGS = ["deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"]

NEWLOCALE_RE = re.compile(r'NewLocale\(\s*"[^"]+"\s*,\s*"[^"]+"')
GUARD_RE = re.compile(r'^\s*if\s+not\s+L\s+then\s+return\s+end\s*$')
KEY_LINE_RE = re.compile(r'''^L\[(["'])((?:\\.|(?!\1).)*)\1\]\s*=\s*(.*)$''')


def read_existing(filepath):
    """key -> translated value, from an existing locale file (both value styles)."""
    if not os.path.isfile(filepath):
        return {}
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    out = {}
    for m in re.finditer(r'L\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"', content):
        out[unescape_lua(m.group(1))] = unescape_lua(m.group(2))
    for m in re.finditer(r'L\["((?:[^"\\]|\\.)*)"\]\s*=\s*\[\[(.*?)\]\]', content, re.DOTALL):
        out[unescape_lua(m.group(1))] = m.group(2)  # bracket content is raw
    return out


def sync_one(en_lines, addon_name, lang, existing):
    """Produce the full list of output lines for one target language."""
    out = []
    i = 0
    while i < len(en_lines):
        line = en_lines[i]
        stripped = line.strip()

        if NEWLOCALE_RE.search(line):
            out.append(f'local L = LibStub("AceLocale-3.0"):NewLocale("{addon_name}", "{lang}")\n')
            out.append("if not L then return end\n")
            i += 1
            continue
        if GUARD_RE.match(line):       # original guard already re-emitted above
            i += 1
            continue

        m = KEY_LINE_RE.match(stripped)
        if not m:                      # comment / blank / other -> copy verbatim
            out.append(line)
            i += 1
            continue

        key = unescape_lua(m.group(2))
        rest = m.group(3)
        is_multiline_bracket = rest.startswith("[[") and "]]" not in rest

        # How many enUS lines does this entry span?
        consumed = 1
        if is_multiline_bracket:
            j = i + 1
            while j < len(en_lines) and "]]" not in en_lines[j]:
                j += 1
            consumed = (j - i) + 1

        translated = existing.get(key)
        if translated is None:
            # Fallback: copy the English entry exactly (structure preserved).
            out.extend(en_lines[i:i + consumed])
        elif is_multiline_bracket or rest.startswith("[["):
            out.append(f'L["{escape_lua(key)}"] = [[{translated}]]\n')
        else:
            out.append(f'L["{escape_lua(key)}"] = "{escape_lua(translated)}"\n')

        i += consumed
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?", default=".", help="Addon dir or its Locales dir (default: .)")
    ap.add_argument("--lang", action="append", help="Target language (repeatable). Default: existing files.")
    ap.add_argument("--dry-run", action="store_true", help="Report changes without writing")
    args = ap.parse_args()

    _, locales_dir, addon_name = resolve_paths(args.path)
    enus = os.path.join(locales_dir, "enUS.lua")
    if not os.path.isfile(enus):
        ap.error(f"enUS.lua not found at {enus}")

    if args.lang:
        langs = args.lang
    else:
        langs = sorted(
            os.path.splitext(f)[0] for f in os.listdir(locales_dir)
            if f.endswith(".lua") and f not in ("enUS.lua", "Locales.lua")
        ) or STANDARD_LANGS

    with open(enus, "r", encoding="utf-8") as f:
        en_lines = f.readlines()

    print(f"Syncing {len(langs)} locale(s) to enUS.lua — {addon_name}")
    backup = None
    if not args.dry_run:
        backup = os.path.join(locales_dir, f"backup_{datetime.now():%Y%m%d_%H%M%S}")
        os.makedirs(backup, exist_ok=True)

    for lang in langs:
        target = os.path.join(locales_dir, f"{lang}.lua")
        existing = read_existing(target)
        new_lines = sync_one(en_lines, addon_name, lang, existing)
        new_text = "".join(new_lines)

        old_text = ""
        if os.path.isfile(target):
            with open(target, "r", encoding="utf-8") as f:
                old_text = f.read()

        if new_text == old_text:
            print(f"  unchanged {lang}.lua")
            continue
        print(f"  {'would update' if args.dry_run else 'updated'} {lang}.lua "
              f"({len(existing)} existing translation(s) kept)")
        if not args.dry_run:
            if old_text:
                shutil.copy2(target, os.path.join(backup, f"{lang}.lua"))
            with open(target, "w", encoding="utf-8") as f:
                f.write(new_text)

    if backup and os.path.isdir(backup) and os.listdir(backup):
        print(f"Backups: {backup}")


if __name__ == "__main__":
    main()
