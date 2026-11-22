# Version names and where they come from

[中文](zh-CN/versions.md) | [English](versions.md)

This page says what each name means, where the plugin gets the list from, and what happens when a name is not there. The examples are from the indexes as they were on 2026-11-21 ([tests/fixtures/index/README.md](../tests/fixtures/index/README.md)).

## Where the list comes from

The plugin reads two indexes:

| Index | Address | Needed |
| --- | --- | --- |
| Zig's | https://ziglang.org/download/index.json | yes: the official releases and `master`, the nightly |
| Mach's | https://machengine.org/zig/index.json | no: the builds that the Mach project names |

`vfox search zig` and `vfox install` read both, and `vfox use` reads them only for a name that is neither an installed version nor a number (see [`vfox use`](#vfox-use)). Mach's index is optional: when it cannot be read, the plugin prints a warning on standard error and lists the official releases alone, so an outage of one index does not stop the other from working.

## Names

| Name | Example | Meaning |
| --- | --- | --- |
| a version | `0.13.0`, `0.17.1` | an official release |
| a version | `0.14.0-dev.2577+271452d22` | a development build, with the commit after `+` |
| `latest` | | the newest official release, which is the first line of `vfox search zig` |
| `nightly` | | the master build of Zig on ziglang.org |
| a Mach name | `2024.11.0-mach`, `mach-latest` | a development build that the Mach project names |

Names are matched exactly. A version installs under its own version, so `vfox install zig@latest` installs `0.17.1` under the name `0.17.1`, and `vfox list zig` shows that name. Installs are named the same way whatever name you typed: `zig@nightly` installs `0.18.0-dev.1260+833623422`.

## The list and its order

`vfox search zig` prints the official releases first, newest first, and then the development builds, newest first. vfox takes the first line as the latest version for `zig@latest`, so the order is what makes `latest` the newest release and not the newest nightly.

Versions compare as semantic versions do: `0.17.1` is newer than `0.17.0`, and a development build such as `0.17.0-dev.2228+955228b68` is older than its release `0.17.0`.

The note on each line gives the names the build has, separated by commas. One build can have several names, as the Mach builds do:

```
0.17.1                     latest
0.18.0-dev.1260+833623422  nightly
0.18.0-dev.935+ead8f5a7a   2026.10.22-mach, mach-latest
```

## Downloads and checksums

Each build downloads from the address its index gives for the platform:

- A Zig release or nightly downloads from ziglang.org.
- A Mach build downloads from the address the index gives as `zigTarball` (ziglang.org). Most Mach builds are not on ziglang.org: in the index of 2026-11-21, ziglang.org has only the newest of the ten, `2026.10.22-mach`, which `mach-latest` names. For the others, the index also gives the archive on Mach's package host, under `tarball`. For those builds, `vfox install` asks ziglang.org for the archive with a HEAD request first, and installs from Mach's package host when that request fails.

Every download is checked against the SHA-256 that the index lists for it. vfox prints `Verifying checksum` and stops if the archive does not match. Both addresses of a Mach build carry the same checksum, so the check holds whichever one the archive came from.

## When a name does not work

| What you see | Why | What to do |
| --- | --- | --- |
| `zig 9.9.9 is not listed for linux/amd64` | the index has no build of that name for your platform | run `vfox search zig`; the platform is in the message |
| `install requires specifying a version for zig` | `vfox install zig` was run without a name | give a name, such as `zig@latest` |
| `WARNING: cannot download https://machengine.org/zig/index.json: ...; listing the official releases only` | Mach's index could not be read | check the network; the official releases still work |
| `cannot download https://ziglang.org/download/index.json: ...` | Zig's index could not be read, so nothing can be listed or installed | check the network, and that ziglang.org is reachable |

## `vfox use`

`vfox use` selects an installed version. Those names need no network:

- a version that is installed, such as `zig@0.13.0`, or a bare or dotted number such as `zig@0.13`, which vfox matches against the installed versions itself.

The other names, `latest`, `nightly` and the Mach names, are looked up in the index, so `vfox use` needs the network for them. Once the version a name refers to is installed, `vfox use` selects it. Until then vfox reports the name as not installed, and `vfox install` installs it.

## Platforms

The plugin looks each platform up by the names the index uses. The table gives the vfox platform (its operating system and architecture, as Go names them) and the names it tries, in order:

| vfox platform | Names in the index |
| --- | --- |
| linux/amd64 | `x86_64-linux` |
| linux/arm64 | `aarch64-linux` |
| linux/386 | `x86-linux`, `i386-linux` |
| linux/arm | `arm-linux`, `armv7a-linux` |
| linux/ppc | `powerpc-linux` |
| linux/ppc64le | `powerpc64le-linux` |
| linux/loong64 | `loongarch64-linux` |
| linux/riscv64 | `riscv64-linux` |
| linux/s390x | `s390x-linux` |
| darwin/amd64 | `x86_64-macos` |
| darwin/arm64 | `aarch64-macos` |
| windows/amd64 | `x86_64-windows` |
| windows/arm64 | `aarch64-windows` |
| windows/386 | `x86-windows`, `i386-windows` |

A platform that is not in the table is looked up under its own Go name. The names that differ from the Go ones are in `arch_names` in `lib/util.lua`, and `tests/util_test.lua` checks them.
