#!/usr/bin/env python3
"""
Shared helpers for the locale tools.

All tools accept a single path argument that may be EITHER:
  - an addon directory (one that contains a `Locales/` subfolder), or
  - a `Locales` directory itself (one that contains `enUS.lua`).

The addon NAME (as used by AceLocale's NewLocale("<name>", ...)) is derived
from the addon folder name, so nothing here is hardcoded to a specific addon.
"""

import os
import re

# A locale key definition:  L["key"] = ...   or   L['key'] = ...
# Handles escaped quotes inside the key and the `<key>` description style.
KEY_DEF_RE = re.compile(r'''L\[(["'])((?:\\.|(?!\1).)*)\1\]\s*=''')

# A locale key *reference* (usage), without the trailing assignment.
KEY_USE_RE = re.compile(r'''L\[(["'])((?:\\.|(?!\1).)*)\1\]''')


def resolve_paths(path):
    """Return (addon_dir, locales_dir, addon_name) from a flexible input path.

    Accepts an addon dir (with a Locales/ subfolder) or a Locales dir directly.
    """
    path = os.path.abspath(path)
    locales = os.path.join(path, "Locales")
    if os.path.isdir(locales):
        addon_dir, locales_dir = path, locales
    elif os.path.basename(path) == "Locales" or os.path.isfile(os.path.join(path, "enUS.lua")):
        locales_dir, addon_dir = path, os.path.dirname(path)
    else:
        # No Locales/ found; assume the path is the addon dir anyway.
        addon_dir, locales_dir = path, locales
    return addon_dir, locales_dir, os.path.basename(addon_dir)


def unescape_lua(s):
    return s.replace(r'\\', '\\').replace(r'\"', '"').replace(r"\'", "'").replace(r'\n', '\n').replace(r'\t', '\t')


def escape_lua(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r')


def locale_files(locales_dir, include_template=False):
    """All `<lang>.lua` files in the Locales dir, excluding the Locales.xml loader
    and (by default) the `Locales.lua` aggregator if present."""
    out = []
    if not os.path.isdir(locales_dir):
        return out
    for name in sorted(os.listdir(locales_dir)):
        if not name.endswith(".lua"):
            continue
        if name == "Locales.lua" and not include_template:
            continue
        out.append(os.path.join(locales_dir, name))
    return out


def extract_key_defs(filepath):
    """Return list of (key, line_number) for every L["..."] = definition."""
    keys = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            m = KEY_DEF_RE.match(line.strip())
            if m:
                keys.append((unescape_lua(m.group(2)), line_num))
    return keys


def iter_code_files(addon_dir, exts=(".lua", ".xml")):
    """Yield non-locale, non-library source files under the addon dir."""
    for root, dirs, files in os.walk(addon_dir):
        dirs[:] = [d for d in dirs
                   if not d.startswith(".") and d not in ("Libs", "Locales", ".release")]
        for fn in files:
            if fn.endswith(exts):
                yield os.path.join(root, fn)
