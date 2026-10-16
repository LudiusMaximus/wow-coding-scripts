# wow-coding-scripts

Bash scripts for maintaining and releasing World of Warcraft addons. They are written for WSL (Ubuntu).

## Setup

In a fresh WSL:

```bash
sudo apt install zip jq rsync subversion
```

The upload tokens go into `include_tokens.sh` next to the scripts. It is in `.gitignore`, so create it yourself:

```bash
#!/usr/bin/env bash

CF_API_KEY=...
WOWI_API_TOKEN=...
WAGO_API_KEY=...
```

## release.sh

Packs the addon in the current folder and uploads it to CurseForge, and to Wago and WoWInterface if the addon is on those as well.

```bash
cd MyAddon
git tag -a 1.2.3 -m "What changed."
bash ../wow-coding-scripts/release.sh
```

- The version is `git describe`, so tag the commit first. A commit after the tag gives versions like `1.2.3-4-gabc1234`.
- The changelog is made from the messages of the last 15 annotated tags reachable from the current branch, so the tag message is the changelog entry. A release branch has to be merged back (not rebased) for its tags to show up in the changelogs of the main branch.
- The working tree is packed as it is, including uncommitted changes, so release from a clean checkout of the tagged commit.
- What stays out of the zip is listed in `package-excludes.txt`.
- `@project-version@` in the .toc files is replaced by the version.
- The upload targets and game versions come from the .toc files: `## Interface` (one or several versions separated by commas), `## X-Curse-Project-ID`, and optionally `## X-Wago-ID` and `## X-WoWI-ID`.

### Checks before a release

`release.sh` aborts if any of these fail, before anything is uploaded:

- `check-minor.sh`: a library whose code changed since the last tag has to raise its LibStub MINOR.
- `check-dev-code.sh`: no development code may be switched on (see below).
- `check-references.sh`: every file the .toc and .xml files load must still be in the packed folder, so that `package-excludes.txt` cannot leave out something the addon needs.

All of them can be run on their own as well, e.g. `bash check-dev-code.sh MyAddon`.

## Development code

Code that is only meant for development, such as opening the options after every reload, goes into a debug block. The first line is the switch.

Switched on, the code runs, and `release.sh` refuses to release:

```lua
--@debug@
MyAddon:OpenOptions()
--@end-debug@]===]
```

Switched off, the block is a Lua comment up to the `]===]` of its last line, and the release goes ahead:

```lua
--[===[@debug@
MyAddon:OpenOptions()
--@end-debug@]===]
```

The last line is the same in both cases. While the block is switched on, it is an ordinary comment.

- Lua files only. Each marker goes on a line of its own, and blocks do not nest.
- `]===]` must not appear inside a block, as it would end the comment early.
- A marker spelt slightly differently, such as `-- @debug@`, is an error, because its code would otherwise run unnoticed. For the same reason, don't write the markers inside ordinary comments.

For anything else that has to be undone before the next release, write `@no-release@` anywhere in a line of a .lua, .xml or .toc file, commented out or not. As long as it is there, the release is refused.

The switched-off form is the same one the BigWigs packager gives these blocks in its zips. Unlike that packager, `release.sh` never changes code by itself: it stops and leaves the switching to you.

## Other scripts

- `update-libs.sh <folder>`: for every addon under the folder that has a `.pkgmeta`, fetches the libraries listed under `externals` into the addon's folder.
- `pull-all.sh <folder>`: fetches and pulls every git repository under the folder, in parallel.
- `locale-tools/`: Python tools for AceLocale-3.0 locale files. See [its README](locale-tools/README.md).
