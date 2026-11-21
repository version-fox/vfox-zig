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

//go:build windows

package e2e

import (
	"archive/zip"
	"encoding/base64"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf16"
)

// The system copy is zig 0.12.1 for Windows, with the SHA-256 that the index of
// ziglang.org lists for the archive (tests/fixtures/index).
const (
	systemArchiveURL    = "https://ziglang.org/download/" + systemVersion + "/zig-windows-x86_64-" + systemVersion + ".zip"
	systemArchiveSHA256 = "52459b147c2de4d7c28f6b1a4b3d571c114e96836bf8e31c953a7d2f5e94251c"
	systemDirName       = "zig-windows-x86_64-" + systemVersion
	zigExecutable       = "zig.exe"
)

// hookSetup sets up vfox's shell hook in the PowerShell that runs it, as an
// interactive shell has it.
const hookSetup = "Invoke-Expression ((& vfox activate pwsh) | Out-String)"

// unpack extracts a .zip archive into dest.
func unpack(t *testing.T, archive, dest string) {
	t.Helper()
	reader, err := zip.OpenReader(archive)
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	root := filepath.Clean(dest) + string(os.PathSeparator)
	for _, f := range reader.File {
		target := filepath.Join(dest, filepath.FromSlash(f.Name))
		if !strings.HasPrefix(target, root) {
			t.Fatalf("%s has an entry outside its folder: %s", archive, f.Name)
		}
		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o755); err != nil {
				t.Fatal(err)
			}
			continue
		}
		if err := extractFile(f, target); err != nil {
			t.Fatal(err)
		}
	}
}

// extractFile writes one file of a zip archive to target.
func extractFile(f *zip.File, target string) error {
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	src, err := f.Open()
	if err != nil {
		return err
	}
	defer src.Close()
	dst, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.Copy(dst, src); err != nil {
		dst.Close()
		return err
	}
	return dst.Close()
}

// vfoxOutcome runs vfox with args in the work directory, in a PowerShell that has
// the hook set up. vfox needs the hook for the commands that change the version,
// such as use, and for an uninstall that switches to another version.
func (h *harness) vfoxOutcome(t *testing.T, args ...string) outcome {
	t.Helper()
	return h.powershell(t, hookSetup+"; & vfox "+psArgs(args)+"; exit $LASTEXITCODE")
}

// zig runs zig with args in the work directory, and returns its output on both
// streams. The environment of the global zig is applied first, as the shell hook
// does between prompts.
func (h *harness) zig(t *testing.T, args ...string) string {
	t.Helper()
	script := hookSetup + "; Invoke-Expression ((& vfox env -s pwsh) | Out-String); & zig " + psArgs(args) + " 2>&1 | Out-String"
	return h.powershell(t, script).combined()
}

// powershell runs script in PowerShell 7, in the work directory, and returns its
// outcome.
func (h *harness) powershell(t *testing.T, script string) outcome {
	t.Helper()
	return h.execute(t, "pwsh", "-NoProfile", "-NonInteractive", "-EncodedCommand", encodePowerShell(script))
}

// psArgs quotes each argument as a PowerShell string literal, separated by spaces.
func psArgs(args []string) string {
	quoted := make([]string, 0, len(args))
	for _, arg := range args {
		quoted = append(quoted, psQuote(arg))
	}
	return strings.Join(quoted, " ")
}

// psQuote quotes s as one PowerShell string literal.
func psQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}

// encodePowerShell encodes script for pwsh -EncodedCommand: the base64 of its
// UTF-16 little-endian bytes. The command line then carries no quotes of the
// script for the command line parser to read.
func encodePowerShell(script string) string {
	units := utf16.Encode([]rune(script))
	buf := make([]byte, 0, 2*len(units))
	for _, u := range units {
		buf = append(buf, byte(u), byte(u>>8))
	}
	return base64.StdEncoding.EncodeToString(buf)
}

// runnable reports whether path is a regular file, which is what zig.exe is on
// Windows.
func runnable(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}
