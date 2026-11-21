// Copyright 2026 Han Li and contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Package e2e runs the end-to-end checks of this plugin with a real vfox, on
// Linux and on Windows. The plugin is registered from the checkout the test runs
// in, so a change is tested as it stands, and the checks run against the real
// indexes and downloads.
//
// Run them from this directory, with vfox 1.1.0 or later on PATH:
//
//	go test -v -count=1 -run TestE2E .
//
// The checks need network access to ziglang.org and machengine.org. docs/e2e.md
// says what each platform needs.
package e2e

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

// The Mach build used below, and the zig installed as a system copy. The names
// and versions are the ones in the indexes that tests/fixtures/index holds.
const (
	machName      = "2024.11.0-mach"
	machVersion   = "0.14.0-dev.2577+271452d22"
	systemVersion = "0.12.1"
)

// helloSource prints with std.debug.print, so it compiles only against the
// standard library of the zig that runs it.
const helloSource = `const std = @import("std");

pub fn main() void {
    std.debug.print("hello from zig\n", .{});
}
`

// TestE2E runs the checks in order, and stops at the first failure: each check
// relies on the ones before it.
func TestE2E(t *testing.T) {
	h := newHarness(t)
	steps := []struct {
		name string
		run  func(*testing.T)
	}{
		{"vfox is 1.1.0 or later", h.checkVfox},
		{"standard error is read", h.checkUsageOnStderr},
		{"register the plugin from this checkout", h.addPlugin},
		{"vfox search zig", h.checkSearch},
		{"install a pinned release", h.installPinned},
		{"the standard library is found from the installed zig", h.checkStandardLibrary},
		{"install latest", h.installLatest},
		{"install a Mach build by its name", h.installMach},
		{"a version the index does not list fails", h.checkMissing},
		{"a zig that vfox did not install is linked with link --detect", h.checkSystemZig},
	}
	for _, step := range steps {
		if !t.Run(step.name, step.run) {
			t.FailNow()
		}
	}
}

// checkVfox requires vfox 1.1.0 or later, which has the Detect hook that
// link --detect uses.
func (h *harness) checkVfox(t *testing.T) {
	t.Helper()
	found := versionIn(h.vfox(t, "--version"))
	if found == "" {
		t.Fatal("vfox --version names no version")
	}
	if compareVersions(found, "1.1.0") < 0 {
		t.Fatalf("vfox 1.1.0 or later is needed for link --detect, found: %s", found)
	}
	t.Logf("PASS vfox %s is 1.1.0 or later", found)
}

// checkUsageOnStderr checks that standard error is read. vfox writes this usage
// error to standard error alone, so the check fails if that output is lost.
func (h *harness) checkUsageOnStderr(t *testing.T) {
	t.Helper()
	o := h.vfoxOutcome(t, "link")
	if o.code == 0 {
		t.Fatalf("vfox link without arguments should fail:\n%s", o.combined())
	}
	expectContains(t, "vfox link without arguments writes its usage to standard error", o.stderr, "usage: vfox link")
}

// addPlugin registers the plugin from the checkout. The notes that vfox info
// prints point to the README, which lists the names.
func (h *harness) addPlugin(t *testing.T) {
	t.Helper()
	archive := filepath.Join(h.work, "zig.zip")
	h.zipPlugin(t, archive)
	h.vfox(t, "add", "zig", "--source", archive)
	t.Log("PASS vfox add zig --source <the checkout>")
	expectContains(t, "vfox info zig points to the README", h.vfox(t, "info", "zig"), "README.md")
}

// checkSearch checks the listing: the releases, the nightly, a Mach build and the
// latest note.
func (h *harness) checkSearch(t *testing.T) {
	t.Helper()
	h.search = h.vfox(t, "search", "zig")
	expectContains(t, "the search lists 0.13.0", h.search, "0.13.0")
	expectContains(t, "the search names the nightly", h.search, "nightly")
	expectContains(t, "the search names a Mach build", h.search, machName)
	expectContains(t, "the search marks a release as latest", h.search, "latest")
}

// installPinned installs a release by its number, and checks the zig it makes
// the global one.
func (h *harness) installPinned(t *testing.T) {
	t.Helper()
	install := h.vfox(t, "install", "zig@0.13.0")
	// vfox prints this only when the download has a checksum to compare with.
	expectContains(t, "the download is verified against its checksum", install, "Verifying checksum")
	h.useGlobal(t, "zig@0.13.0")
	expectContains(t, "zig 0.13.0 is on PATH", h.zig(t, "version"), "0.13.0")
}

// checkStandardLibrary compiles and runs a program against the standard library
// of the installed zig.
func (h *harness) checkStandardLibrary(t *testing.T) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(h.work, "hello.zig"), []byte(helloSource), 0o644); err != nil {
		t.Fatal(err)
	}
	expectContains(t, "zig run compiles against the std library", h.zig(t, "run", "hello.zig"), "hello from zig")
}

// installLatest checks that latest is the release the search marks latest, and
// not the newest nightly.
func (h *harness) installLatest(t *testing.T) {
	t.Helper()
	h.vfox(t, "install", "zig@latest")
	expected := latestRelease(h.search)
	if expected == "" {
		t.Fatalf("the search output names no release as latest:\n%s", h.search)
	}
	t.Logf("PASS search marks %s as latest", expected)
	// use maps the name latest to the installed version it names.
	h.useGlobal(t, "zig@latest")
	expectContains(t, "zig@latest selects the release search marks latest", h.zig(t, "version"), expected)
}

// installMach installs a Mach build by its name.
func (h *harness) installMach(t *testing.T) {
	t.Helper()
	h.vfox(t, "install", "zig@"+machName)
	h.useGlobal(t, "zig@"+machName)
	expectContains(t, "zig@"+machName+" selects the Mach build", h.zig(t, "version"), machVersion)
}

// checkMissing checks that a version the index does not list fails, and that the
// failure names the platform it looked for.
func (h *harness) checkMissing(t *testing.T) {
	t.Helper()
	h.expectVfoxFails(t, "vfox install zig@9.9.9 fails", "is not listed for "+runtime.GOOS+"/"+runtime.GOARCH, "install", "zig@9.9.9")
}

// checkSystemZig links a zig that vfox did not install with link --detect, and
// checks the link, its use, and its removal.
func (h *harness) checkSystemZig(t *testing.T) {
	t.Helper()
	systemRoot := filepath.Join(h.work, "system")
	if err := os.Mkdir(systemRoot, 0o755); err != nil {
		t.Fatal(err)
	}
	archive := filepath.Join(h.work, "system-zig.archive")
	download(t, systemArchiveURL, archive)
	if got := fileSHA256(t, archive); got != systemArchiveSHA256 {
		t.Fatalf("the zig %s archive does not match its checksum, got %s", systemVersion, got)
	}
	unpack(t, archive, systemRoot)
	t.Logf("PASS unpacked zig %s as a system copy", systemVersion)

	// The copy is only on PATH, which is where link --detect looks first.
	systemDir := filepath.Join(systemRoot, systemDirName)
	t.Setenv("PATH", systemDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	// The checks name the last folder of the copy: on Windows a temporary folder
	// can be spelled with 8.3 short names, and vfox may print the full path.
	detect := h.vfox(t, "link", "--detect", "-y", "zig")
	expectContains(t, "link --detect finds the copy on PATH", detect, systemDirName)
	expectContains(t, "link --detect names the version", detect, systemVersion)

	list := h.vfox(t, "list", "zig")
	expectContains(t, "vfox list shows the link", list, systemDirName)

	h.useGlobal(t, "zig@"+systemVersion)
	expectContains(t, "the linked zig runs", h.zig(t, "version"), systemVersion)

	// Versions vfox installed are not offered again, so a second run finds nothing new.
	again := h.vfox(t, "link", "--detect", "-y", "zig")
	expectContains(t, "a second link --detect finds nothing new", again, "No new zig installations found")

	// Removing the link leaves the directory where it was.
	h.vfox(t, "uninstall", "zig@"+systemVersion)
	if !runnable(filepath.Join(systemDir, zigExecutable)) {
		t.Fatal("uninstalling a link removed the system zig")
	}
	t.Log("PASS vfox uninstall removes the link and keeps the system zig")
}
