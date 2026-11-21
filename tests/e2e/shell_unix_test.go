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

//go:build !windows

package e2e

import (
	"os"
	"testing"
)

// The system copy is zig 0.12.1 for Linux, with the SHA-256 that the index of
// ziglang.org lists for the archive (tests/fixtures/index).
const (
	systemArchiveURL    = "https://ziglang.org/download/" + systemVersion + "/zig-linux-x86_64-" + systemVersion + ".tar.xz"
	systemArchiveSHA256 = "8860fc9725c2d9297a63008f853e9b11e3c5a2441217f99c1e3104cc6fa4a443"
	systemDirName       = "zig-linux-x86_64-" + systemVersion
	zigExecutable       = "zig"
)

// hookSetup sets up vfox's shell hook in the bash that runs it, as an interactive
// shell has it. The hook also installs an exit cleanup, which is dropped: each
// bash runs one command and exits, and the work directory is removed at the end
// of the run.
const hookSetup = `eval "$(vfox activate bash)" && trap - EXIT`

// unpack extracts a .tar.xz archive into dest. tar does the xz decompression,
// which the Go standard library does not have.
func unpack(t *testing.T, archive, dest string) {
	t.Helper()
	if o := executeIn(t, dest, "tar", "--extract", "--xz", "--file", archive, "--directory", dest); o.code != 0 {
		t.Fatalf("unpacking %s failed:\n%s", archive, o.combined())
	}
}

// vfoxOutcome runs vfox with args in the work directory, in a bash that has the
// hook set up. vfox needs the hook for the commands that change the version, such
// as use, and for an uninstall that switches to another version.
func (h *harness) vfoxOutcome(t *testing.T, args ...string) outcome {
	t.Helper()
	return h.execute(t, "bash", append([]string{"-c", hookSetup + ` && vfox "$@"`, "bash"}, args...)...)
}

// zig runs zig with args in the work directory, and returns its output on both
// streams. The environment of the global zig is applied first, as the shell hook
// does between prompts. A test has no prompts, so it does not get that by itself.
func (h *harness) zig(t *testing.T, args ...string) string {
	t.Helper()
	script := hookSetup + ` && eval "$(vfox env -s bash)" && zig "$@" 2>&1`
	return h.execute(t, "bash", append([]string{"-c", script, "bash"}, args...)...).combined()
}

// runnable reports whether path is a regular file that can be run.
func runnable(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular() && info.Mode().Perm()&0o111 != 0
}
