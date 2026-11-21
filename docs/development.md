# Development

[中文](zh-CN/development.md) | [English](development.md)

## Layout

```
metadata.lua                  plugin name, version, notes and homepage
hooks/available.lua           vfox search: the versions and their names
hooks/pre_install.lua         vfox install: the download of the name given
hooks/post_install.lua        nothing to do after the unpack
hooks/env_keys.lua            PATH, so that zig runs
hooks/pre_use.lua             vfox use: the installed version a name refers to
hooks/detect.lua              vfox link --detect: the zig already on the machine
lib/util.lua                  the indexes, the names, the order and the platform
lib/detect_zig.lua            finding zig installs by their executable and lib/std
tests/*_test.lua              offline hook tests, run by vfox plugin test
tests/fixtures/index/         copies of the two indexes the tests answer with
tests/e2e/                    the end-to-end checks, one Go test for Linux and Windows
tests/e2e/linux/Dockerfile    the image that runs them on Linux, in a container
Injection.lua                 type hints for what vfox injects, never loaded
stylua.toml, .luarc.json      formatting, and the Lua language server's settings
.licenserc.yaml               license headers
opencode.jsonc                lets OpenCode agent sessions in this repository run git push, gh pr create and gh pr comment without asking
README.md, docs/              the documentation; README_CN.md and docs/zh-CN/ are the Chinese version
```

vfox loads `metadata.lua`, calls the hook a command needs, and puts `PLUGIN` and `RUNTIME` (`osType`, `archType`, `version`) in scope. `osType` and `archType` are the GOOS and GOARCH of the vfox binary, and `osType` is `darwin` on macOS (the index calls it `macos`).

## What runs for a command

| You run | Hooks |
| --- | --- |
| `vfox search zig` | `Available` |
| `vfox install zig@latest` | `PreInstall` returns the URL, the name and the SHA-256. vfox downloads, checks and unpacks, then calls `PostInstall` |
| `vfox use zig@latest` | `PreUse` returns the installed name to select. `EnvKeys` provides `PATH` |
| `vfox link --detect zig` | `Detect` returns the zig installs already on the machine (`lib/detect_zig.lua`) |
| `vfox info zig` | the notes in `metadata.lua` |

## Contracts with vfox

These are what the hooks rely on, and what the tests check.

- `Available` returns a list of `{ version, note }`, and vfox takes the first entry as the latest for `zig@latest`. So the order is official releases first, newest first, then the development builds, newest first (`util:releases()`).
- The note is the names of a build, separated by `, `. The newest official release carries `latest`. `PreInstall` and `PreUse` match a name against the versions and then against the names.
- `PreInstall` returns `url`, `version`, `sha256` and `note`. The version is the name of the install. vfox checks the download against `sha256`, which must be the lower-case hex digest that the index gives.
- A Mach build can have two addresses. `util.download_url` makes one HEAD request, to the first address, and falls back to the second only when the first does not answer with 200. A release has one address, so it makes no request.
- `PreUse` returns a table or `nil`, never a bare string (vfox after 1.0.12 rejects a string). It returns `nil` for an installed name and for a bare or dotted number, so `use` reads no index for them.
- `Detect` returns `{ version, path, note }`. `version` must be a name vfox accepts (letters, digits and `._+-`), and `path` is the directory that holds the zig executable.
- `EnvKeys` puts the install directory on `PATH`. zig finds its library beside its executable, so nothing else is set.

## Tests

The offline hook tests run under `vfox plugin test`, which vfox 1.0.13 and later has. It finds every `tests/**/*_test.lua` and runs each file in a VM of its own, so a new test file needs no entry anywhere:

```bash
vfox plugin test .
vfox plugin test . --file tests/available_test.lua
```

Run it from the repository root. The Test Plugin workflow installs the release pinned in `.github/workflows/test.yml`.

A test file calls `test.load()` from `vfox.test` once, and then calls the hooks through the plugin it returns, as in `plugin:PreInstall({ version = "0.13.0" })`. `test.load` takes the platform (`os`, `arch`), the environment variables (`env`) and a function that answers every HTTP request (`http`, which gets `request.url` and `request.method`, and returns `{ status_code, body }` or `nil, err`). The modules in `lib` can be required after it. `RUNTIME.osType` and `RUNTIME.archType` can be changed to try another platform.

The tests answer from the index copies in `tests/fixtures/index`, so they check the plugin against what the indexes really held on 2026-11-21, and they need no network. `tests/fixtures/index/README.md` says how to refresh them. `detect_test.lua` and `detect_windows_test.lua` replace the file system and the commands `io.open` and `io.popen` with a table, and check which directories are reported.

## Lint and format

Everything below runs in CI (`.github/workflows/lint.yml`, `license.yml`). The versions are the ones the workflows pin.

```bash
stylua --check .                      # StyLua 2.5.2, stylua.toml
lua-language-server --check . --checklevel=Warning   # LuaLS 3.19.1, .luarc.json
gofmt -l tests/e2e                    # Go: prints nothing when the files are formatted
(cd tests/e2e && go vet ./... && GOOS=windows go vet ./...)   # Go: vet, for Linux and for Windows
hadolint < tests/e2e/linux/Dockerfile
actionlint                            # the workflows
```

The Go code is checked by `gofmt` and `go vet`. `GOOS=windows go vet` compiles the Windows build of the tests as well.

## License headers

Every source file starts with the Apache 2.0 header of `.licenserc.yaml`. `apache/skywalking-eyes` checks it (`header check`), and `header fix` adds it to files that lack it. Markdown and JSON are not checked.

## Writing the docs

The English pages are in `docs/` and the Chinese ones in `docs/zh-CN/` under the same names; the Chinese README is `README_CN.md`. Each page starts with a link to the other language. A new page goes into the list of both READMEs. Pages that quote an index give the day the data was taken.

## Changes

`docs/changes.md` and `docs/zh-CN/changes.md` describe what changed for a user. A change in behaviour, a fix, or a new hook is listed there in both languages, under a `## Unreleased` heading at the top. The release replaces that heading with the version (see [After a release](#after-a-release)).

## Releasing

A maintainer publishes from **Actions → Plugin → Run workflow** on the default branch, entering a stable plugin version without the `v` prefix. The shared workflow, [plugin-manifest-action](https://github.com/version-fox/plugin-manifest-action), updates `metadata.lua`, creates the version commit and the tag, and publishes the ZIP and the manifest in this repository. No local tag or extra release token is needed. Pull requests run the checks only.

Pushing a version tag publishes too, when `PLUGIN.version` already matches the tag. If publication fails, re-run the failed job to resume it. The workflow follows the shared `@v1` release tool, and updating the tool does not release this plugin.

### After a release

The documentation marks what is newer than the last release with "Unreleased" ("未发布" in Chinese). Once the release is out:

1. Move those entries in [changes.md](changes.md) under a heading for the new version, with the date of the release (`## 0.1.2 (2026-11-21)`), in both languages, and remove the `Unreleased` heading. `grep -rn -i -e unreleased -e 未发布 docs README*` finds what is still marked; after the move, only the notes on these two pages match.
2. Give the date of the index copies in `tests/fixtures/index/README.md` when they are refreshed, and check the examples in [versions.md](versions.md) against them.
