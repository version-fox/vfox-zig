# Using a Zig that is already on the machine

[中文](zh-CN/link.md) | [English](link.md)

If a Zig is already on the machine (from a package manager, Scoop, Homebrew, mise, asdf, zvm, or a copy you unpacked yourself), `vfox link --detect zig` adopts it instead of downloading another copy. It needs vfox 1.1.0 or later (`vfox --version`).

```bash
vfox link --detect zig
```

vfox lists what the plugin found and links what you pick. `vfox link --detect -y zig` links everything without asking. Afterwards `vfox use zig@...` works as usual: `vfox list zig` shows the linked versions with their paths, and `vfox uninstall` removes only the link, leaving the Zig where it is.

## What it finds

- Every `zig` (`zig.exe` on Windows) in the directories of `PATH`, which covers Homebrew, the system packages and the `PATH` entries you set up yourself. A symbolic link is followed to the directory that really holds the executable, so `/usr/bin/zig` that links to `/usr/lib/zig/zig` is reported as `/usr/lib/zig`.
- The version managers, on Linux and macOS: mise (`~/.local/share/mise/installs/zig`), asdf (`~/.asdf/installs/zig`) and zvm (`~/.zvm`). Each keeps a directory per version, and mise and asdf are searched one level deeper as well, since they can keep the zig in a folder inside a version's directory. On Windows, mise (`%USERPROFILE%\.local\share\mise\installs\zig`) and zvm (`%USERPROFILE%\.zvm`) are searched the same way.
- Scoop's apps (`%USERPROFILE%\scoop\apps\zig`) on Windows.
- The system directories: `/usr/local`, `/opt` and `/usr/lib` on Linux and macOS, and `C:\Program Files\zig` on Windows. Each is searched itself and one level below it, so `/opt/zig-linux-x86_64-0.12.1` is found.

## What counts as a Zig

A directory is reported when all of these hold:

- it holds the `zig` executable (`zig.exe` on Windows);
- the standard library sits beside it, at `lib/std/std.zig`, which is the layout of the official archives and what vfox links, so zig finds its library through PATH;
- `zig version` runs and prints a version, which is the name the install gets (`0.13.0`, or `0.14.0-dev.2577+271452d22` for a development build).

These are left out:

- vfox's own installs: everything under its home directory, which is `VFOX_HOME` when that is set and a `.vfox` directory otherwise, and any `cache/zig/v-<version>` directory, where vfox keeps each install, whichever home it was made in;
- shim directories, such as `~/.asdf/shims`, `~/.local/share/mise/shims`, or Chocolatey's `bin`. A shim runs whichever version the manager selected, not the one beside it;
- relative entries on `PATH`;
- a version that is already installed or linked, and a second copy of a version that was found already (the first one found is kept, and `PATH` comes first).

A copy without its `lib/std` is left out, because zig could not find its library there and linking it would give a broken `zig`.

## Linking by hand

Where `--detect` does not look, link the directory by hand. Give the directory that holds the `zig` executable, with its `lib` beside it:

```bash
vfox link zig@0.12.1 /opt/zig-linux-x86_64-0.12.1
vfox use --global zig@0.12.1
```

## Removing a link

`vfox uninstall zig@0.12.1` removes the link and nothing else. The Zig stays where it was, so it is still there for the package manager or the version manager that installed it.
