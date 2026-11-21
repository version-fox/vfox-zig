# vfox-zig

[中文](README_CN.md) | [English](README.md)

vfox-zig is a [vfox](https://vfox.dev/) plugin for the [Zig](https://ziglang.org/) programming language. It installs the official releases, Zig's nightly build, and the development builds that the [Mach](https://machengine.org/) project names. It also adopts a Zig that is already on the machine, instead of downloading another copy.

## Install

Install vfox first. `vfox link --detect zig` needs vfox 1.1.0 or later (`vfox --version` shows yours); the other commands work with earlier versions. Then add the plugin:

```bash
vfox add zig
```

## Use

```bash
vfox search zig                  # list the versions and the names they have
vfox install zig@0.13.0          # install a release by its version
vfox install zig@latest          # install the newest official release
vfox use --global zig@latest     # select an installed version for every shell
zig version
```

Every install is verified against the SHA-256 that the index of ziglang.org (or of Mach) lists for it. The plugin needs network access to those indexes.

Zig installs that are already on the machine can be linked instead of installed again:

```bash
vfox link --detect zig           # list the installs found, and link the ones you pick
vfox link --detect -y zig        # link all of them without asking
```

See [docs/link.md](docs/link.md).

## Version names

| Name | What it installs |
| --- | --- |
| `0.13.0`, `0.17.1`, ... | an official release, under its own version |
| `latest` | the newest official release |
| `nightly` | the master build of Zig on ziglang.org, the newest development build |
| `2024.11.0-mach`, `mach-latest`, ... | a development build that the Mach project names |

`vfox search zig` lists the releases first, newest first, then the development builds, newest first. The note on each line gives its names, such as `latest` or `nightly, mach-latest`. The details, and where the data comes from, are in [docs/versions.md](docs/versions.md).

## Platforms

The plugin installs the build that the index lists for the platform vfox runs on. The latest releases list Linux builds for `x86_64`, `aarch64`, `x86`, `arm`, `riscv64`, `powerpc64le`, `s390x` and `loongarch64`, macOS builds for `x86_64` and `aarch64`, and Windows builds for `x86_64`, `aarch64` and `x86`. Older releases list fewer platforms. A version without a build for your platform is reported as not listed for it, and the list in [docs/versions.md](docs/versions.md#platforms) shows the names that are looked up.

## Documentation

- [Version names and where they come from](docs/versions.md)
- [Using a Zig that is already on the machine](docs/link.md)
- [Changes](docs/changes.md)
- [Development](docs/development.md)
- [End-to-end checks](docs/e2e.md)

## Releasing this plugin

Maintainers can publish from **Actions → Plugin → Run workflow** on the default
branch by entering a stable plugin version without the `v` prefix. The shared
workflow updates `metadata.lua`, creates the version commit and tag, and publishes
the ZIP and manifest in this repository. No local tag or extra release token is
needed. Pull requests run checks only; PR titles no longer trigger publication.

Existing version-tag pushes are supported when `PLUGIN.version` already matches
the tag. If publication fails, re-run the original failed job to resume it.

The workflow follows the shared `@v1` release-tool version. Updating the tool does
not release this plugin. See the [shared workflow documentation](https://github.com/version-fox/plugin-manifest-action)
for the package contract and first-rollout requirements. The steps after a release
are in [docs/development.md](docs/development.md#after-a-release).

## License

Apache License 2.0. See [LICENSE](LICENSE).
