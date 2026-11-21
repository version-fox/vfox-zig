# End-to-end checks

[中文](zh-CN/e2e.md) | [English](e2e.md)

The offline hook tests and the lint run in the Test Plugin and Lint workflows. The end-to-end checks install the plugin into a real vfox, and run it against the real indexes, on Linux and on Windows.

## Linux

In a throwaway container, which needs Docker. From the repository root:

```bash
docker build -t zig-e2e tests/e2e/linux
docker run --rm -v "$PWD:/src:ro" zig-e2e
```

The image is Ubuntu 26.04 with vfox 1.1.0, whose SHA-256 is checked when the image is built. The checkout is mounted read-only, so the run cannot change it, and each run has its own home directory for vfox and the zig caches.

On a Linux host, with vfox 1.1.0 or later on `PATH`, plus `zip`, `curl`, `sha256sum`, `tar` with xz support and `awk`:

```bash
bash tests/e2e/linux/e2e.sh
```

CI runs it on `ubuntu-latest` in the E2E workflow.

## Windows

The Windows checks run in CI, on `windows-latest`, and are not run in a local container. They need vfox 1.1.0 or later and PowerShell 7 on `PATH`:

```powershell
pwsh -NoProfile -File tests/e2e/windows/e2e.ps1
```

They run natively, without Docker. Their work directory has a space in its name, as a Windows temporary path often has one.

## What the checks verify

Both scripts run the same checks, in this order, and stop at the first failure:

1. vfox is 1.1.0 or later, and the plugin is added from this checkout (`vfox add zig --source`). `vfox info zig` points to the README, which lists the names.
2. `vfox search zig` lists `0.13.0`, the `nightly` note, a Mach build's name and the `latest` note.
3. `vfox install zig@0.13.0` verifies the download against its checksum (`Verifying checksum`), and `zig` then reports `0.13.0`.
4. The standard library is found from the installed zig: a program that prints with `std.debug.print` compiles and runs.
5. `vfox install zig@latest` installs the release that the search marks `latest`, and `zig@latest` selects it with `vfox use`. This is the check that `latest` is the newest official release, not the newest nightly.
6. `vfox install zig@2024.11.0-mach` installs a Mach build by its name, and `vfox use` selects it. The build is no longer on ziglang.org, so its download comes from the address the index lists for Mach's package host.
7. `vfox install zig@9.9.9` fails, and names the platform it looked for.
8. A zig that vfox did not install is linked with `vfox link --detect -y zig`. The copy is on `PATH` for the run. The list shows the link, `vfox use` selects the linked zig, a second `link --detect` finds nothing new, and `vfox uninstall` removes the link and leaves the copy in place.

## Network use

Each run downloads about 200 MB: the indexes from ziglang.org and machengine.org, zig 0.13.0 and 0.17.1 and the Mach build from ziglang.org or Mach's package host, and zig 0.12.1 (for the system copy) from ziglang.org. vfox itself is downloaded from GitHub in CI.

## What is not covered

- macOS and arm64 hosts have no end-to-end run. They are covered by the offline tests, which set the platform, and by the index lookups in `docs/versions.md`.
- The Windows script runs only in CI. Locally it was checked with the PowerShell parser and PSScriptAnalyzer.
