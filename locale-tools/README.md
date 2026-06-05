# Localization Management Tools

Addon-agnostic Python utilities for maintaining AceLocale-3.0 (`L["key"] = "value"`)
locale files across any WoW addon.

## Conventions

Every tool takes **one path argument** that may be either:

- an **addon directory** (one containing a `Locales/` subfolder), or
- a **`Locales/` directory** itself (one containing `enUS.lua`).

The path defaults to the current directory if omitted. The addon **name** (used
by `NewLocale("<name>", ...)`) is derived from the addon folder name — nothing is
hardcoded to a specific addon. Run any script with `-h`/`--help` for its options.

`enUS.lua` is treated as the **source of truth** for the canonical key set.

Shared logic (path resolution, key regexes, escaping) lives in `locale_common.py`,
which the other scripts import — keep it alongside them.

## Analysis

### `analyze_locale_usage.py [PATH] [-o OUT.txt]`
Reports which source file(s) reference each `enUS.lua` key. Groups keys by their
primary using-file; flags unused and multi-location strings. Writes a detailed
report (default `locale_usage_analysis.txt`).

### `detect_duplicates.py [PATH]`
Finds keys defined more than once within each locale file, with line numbers.

### `find_unused_strings.py [PATH] [--keys-only]`
Lists `enUS.lua` keys not referenced in any `.lua`/`.xml` (excludes `Locales/`,
`Libs/`, `.release/`). `--keys-only` prints bare keys for piping into the purge tool.

### `validate_locales.py [PATH] [--show-extra]`
Checks every locale file defines the same keys as `enUS.lua`; reports missing
(and optionally extra) keys. Exits non-zero if anything is missing — handy in CI.

## Maintenance

### `fix_locales.py [PATH] --replace OLD NEW [...] [--dry-run]`
Literal find/replace across all locale files (e.g. after renaming a key).
`--replace` is repeatable.

### `purge_unused_strings.py [PATH] (--key K | --from-file F) [--dry-run]`
Removes the given keys from every locale file (timestamped backup first).
`--from-file -` reads stdin, so it composes with `find_unused_strings.py`:

```bash
python find_unused_strings.py MyAddon --keys-only | \
    python purge_unused_strings.py MyAddon --from-file -
```

## Synchronization

### `sync_locales.py [PATH] [--lang L ...] [--dry-run]`
Rewrites each `<lang>.lua` to mirror `enUS.lua`'s exact structure (key order,
comments, blank lines, `"..."` vs `[[ ]]` shape), **preserving existing
translations** and falling back to the English value for untranslated keys. This
keeps every locale a structural twin of `enUS.lua`. Targets default to the
`<lang>.lua` files already present (else the standard WoW set). Backs up before
writing. Carries **no** hardcoded translations — maintain those in the locale
files themselves.

> Note: on first run it normalises the `NewLocale(...)` header to two lines and
> drops any leading UTF-8 BOM. Harmless and one-time.

## Organization

### `reorganize_locale.py [PATH]`
Writes `enUS_reorganized.lua` next to `enUS.lua`, grouping each string under a
`-- <source file>` section based on real usage (plus an `UNUSED` section). Review,
then rename over `enUS.lua` manually.

## Typical workflows

**Add new strings**
```bash
# 1. add strings to enUS.lua, then propagate as English placeholders:
python sync_locales.py MyAddon
python validate_locales.py MyAddon
```

**Clean up dead strings**
```bash
python find_unused_strings.py MyAddon            # review first!
python find_unused_strings.py MyAddon --keys-only | \
    python purge_unused_strings.py MyAddon --from-file - --dry-run
python detect_duplicates.py MyAddon
```

**Pre-release check**
```bash
python detect_duplicates.py MyAddon
python find_unused_strings.py MyAddon
python validate_locales.py MyAddon
```

## Notes

- All scripts assume AceLocale-3.0 format and preserve `[[ ]]` multiline strings.
- `--dry-run` is available on the mutating tools (`sync`, `purge`, `fix`).
- Mutating tools write timestamped backups; still test on a copy for anything bulk.
