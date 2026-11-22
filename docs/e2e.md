# End-to-end checks

[中文](zh-CN/e2e.md) | [English](e2e.md)

The offline hook tests and the lint run in the Test Plugin and Lint workflows. The end-to-end checks install the plugin into a real vfox, and run it against the real indexes, on Linux and on Windows. They are one Go test in `tests/e2e`, and the same checks run on both systems.

## Linux

In a throwaway container, which needs Docker. From the repository root:

```bash
docker build -t zig-e2e tests/e2e/linux
docker run --rm -v "$PWD:/src:ro" zig-e2e
```

The image is `golang:1.27.1` with vfox 1.1.0, whose SHA-256 is checked when the image is built, and with xz for the system copy. The checkout is mounted read-only, so the run cannot change it, and each run has its own home directory for vfox and the zig caches.

On a Linux host, with vfox 1.1.0 or later, Go and `tar` with xz support on `PATH`:

```bash
cd tests/e2e
go test -v -count=1 -run TestE2E .
```

CI runs it on `ubuntu-latest` in the E2E workflow.

## Windows

The same test runs natively, without Docker. It needs vfox 1.1.0 or later, Go and PowerShell 7 on `PATH`:

```powershell
cd tests/e2e
go test -v -count=1 -run TestE2E .
```

CI runs it on `windows-latest`. Its work directory has a space in its name, as a Windows temporary path often has one.

## What the checks verify

The test runs these checks as subtests, in this order, and stops at the first failure:

1. vfox is 1.1.0 or later, and standard error is read: `vfox link` without arguments writes its usage to standard error. The plugin is added from this checkout (`vfox add zig --source`), and `vfox info zig` points to the README, which lists the names.
2. `vfox search zig` lists `0.13.0`, the `nightly` note, a Mach build's name and the `latest` note.
3. `vfox install zig@0.13.0` verifies the download against its checksum (`Verifying checksum`), and `zig` then reports `0.13.0`.
4. The standard library is found from the installed zig: a program that prints with `std.debug.print` compiles and runs.
5. `vfox install zig@latest` installs the release that the search marks `latest`, and `zig@latest` selects it with `vfox use`. This is the check that `latest` is the newest official release, not the newest nightly.
6. `vfox install zig@2024.11.0-mach` installs a Mach build by its name, and `vfox use` selects it. The build is no longer on ziglang.org (checked on 2026-11-22), so its download comes from the address the index lists for Mach's package host.
7. `vfox install zig@9.9.9` fails, and names the platform it looked for.
8. A zig that vfox did not install is linked with `vfox link --detect -y zig`. The copy is on `PATH` for the run. The list shows the link, `vfox use` selects the linked zig, a second `link --detect` finds nothing new, and `vfox uninstall` removes the link and leaves the copy in place.

On Linux and macOS, vfox refuses to change the version unless its shell hook is set up, and an uninstall that switches to another version needs it too. So every vfox command in the checks runs in a shell where `vfox activate` has run: bash on Linux, PowerShell 7 on Windows. The checks that run zig apply the environment of the global zig first, as the shell hook does between prompts.

## Network use

Each run downloads about 200 MB: the indexes from ziglang.org and machengine.org, zig 0.13.0, the latest release and the Mach build from ziglang.org or Mach's package host, and zig 0.12.1 (for the system copy) from ziglang.org. vfox itself is downloaded from GitHub in CI.

A vfox command whose output reports a timeout is run again, up to three times in all, because the indexes and the downloads come over the network. Any other failure stops the run at once.

## What is not covered

- macOS and arm64 hosts have no end-to-end run. They are covered by the offline tests, which set the platform, and by the index lookups in `docs/versions.md`.
- The Windows checks run in CI and on a Windows host. Locally, `GOOS=windows go vet` compiles the Windows build of the test.
