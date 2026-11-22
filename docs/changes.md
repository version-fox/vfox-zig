# Changes

[中文](zh-CN/changes.md) | [English](changes.md)

What changed in each release, as a user notices it. GitHub's release pages list the commits.

## Unreleased

- `vfox link --detect zig` leaves out the zig that vfox installed under a custom `VFOX_HOME`, and the ones that vfox made under another home. Before, they were offered as zig installs already on the machine. See [link.md](link.md).
- The warnings about an index that cannot be read go to standard error. Before, they went to standard output, so the warning about Mach's index came first in `vfox search zig | head -1`.

## 0.1.2 (2026-11-21)

- `vfox link --detect zig` links the Zig installs that are already on the machine: those on `PATH`, in the version managers (mise, asdf, zvm, Scoop) and in the system directories. It needs vfox 1.1.0 or later. See [link.md](link.md).
- `vfox install zig@latest` installs the newest official release. Before, it installed the newest nightly: vfox takes the first version of `vfox search zig` as the latest, and the nightly was first. Official releases are now listed first, newest first, then the development builds. See [versions.md](versions.md#the-list-and-its-order).
- `vfox use zig@latest`, `zig@nightly` and a Mach name select the installed version they name. Before, `use` did not find them.
- A Mach build that ziglang.org no longer has, such as `2024.11.0-mach`, installs from the address that the Mach index gives for it. Before, the install could fail with an empty download address, and the address it used depended on the order of the index.
- `vfox search zig` names each build once, with its names separated by commas, such as `2026.10.22-mach, mach-latest`. Before, the notes could read `nightly|2024.11.0-mach`, and a Mach build could carry the nightly's name.
- Versions sort by semantic versioning: `0.17.0` is listed above `0.17.0-dev.2228+955228b68`, which was listed above it before.
- The Mach index is optional. When it cannot be read, `vfox search zig` and `vfox install` print a warning and use the official releases. Before, one unreachable index stopped every command.
- A failed download of an index names the address and the reason. Before, the message was a Lua error about a nil value.
- Platforms: 32-bit ARM (`armv7a` in the older releases, `arm` in the newer ones), 32-bit PowerPC, LoongArch and POWER little endian (`ppc64le`) are looked up under the names the index uses.
- `vfox info zig` links to the README, which lists the names and the commands.
- The repository gains bilingual documentation, the lint and license checks, offline tests of the hooks, and end-to-end checks of Linux and Windows.

## 0.1.1

- The first version in this repository: the `Available`, `PreInstall`, `PostInstall`, `PreUse` and `EnvKeys` hooks over the index of ziglang.org, and the Mach index. The history is in `git log`.
