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

package e2e

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"
)

// harness is the state of one run: a new directory for its files, the checkout
// the plugin comes from, and the output of vfox search, which the install of
// latest reads.
type harness struct {
	work   string
	repo   string
	search string
}

// newHarness prepares a run. The work directory is new and outside the checkout.
// On Windows its name has a space in it, as temporary paths there often do.
func newHarness(t *testing.T) *harness {
	t.Helper()
	repo, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	prefix := "zig-e2e-"
	if runtime.GOOS == "windows" {
		prefix = "zig e2e "
	}
	work, err := os.MkdirTemp("", prefix)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.RemoveAll(work); err != nil {
			t.Logf("removing %s: %v", work, err)
		}
	})
	// A private home for vfox, so the run never touches the real one. vfox keeps
	// its user and shared directories under the home directory's .vfox, which is
	// the default, so the installs made here are not taken for system installs.
	home := filepath.Join(work, "home")
	if err := os.Mkdir(home, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)
	if old, ok := os.LookupEnv("VFOX_HOME"); ok {
		os.Unsetenv("VFOX_HOME")
		t.Cleanup(func() { os.Setenv("VFOX_HOME", old) })
	}
	return &harness{work: work, repo: repo}
}

// outcome is what a program ended with: its exit code, and what it wrote to
// standard output and to standard error.
type outcome struct {
	code   int
	stdout string
	stderr string
}

// combined returns the output on both streams, standard output first.
func (o outcome) combined() string {
	return o.stdout + o.stderr
}

// execute runs program with args in the work directory.
func (h *harness) execute(t *testing.T, program string, args ...string) outcome {
	t.Helper()
	return executeIn(t, h.work, program, args...)
}

// executeIn runs program with args in dir, and keeps its output on each stream
// apart. A program that cannot start stops the test.
func executeIn(t *testing.T, dir, program string, args ...string) outcome {
	t.Helper()
	cmd := exec.Command(program, args...)
	cmd.Dir = dir
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	o := outcome{}
	var exitErr *exec.ExitError
	if err := cmd.Run(); err != nil {
		if !errors.As(err, &exitErr) {
			t.Fatalf("starting %s: %v", program, err)
		}
		o.code = exitErr.ExitCode()
	}
	o.stdout = stdout.String()
	o.stderr = stderr.String()
	return o
}

// networkAttempts is how many times a vfox command is run when it times out. The
// indexes and the downloads come over the network, and a timeout there says
// nothing about the plugin: vfox reports a download that times out as "request
// timeout", whether the lookup, the connection or the handshake was slow. A
// command that timed out leaves nothing behind (vfox removes a partial install
// after an ordinary error), so the next attempt starts from the beginning.
const networkAttempts = 3

// timedOut reports whether a command failed with a timeout in its output.
func timedOut(o outcome) bool {
	return o.code != 0 && strings.Contains(strings.ToLower(o.combined()), "timeout")
}

// vfoxAttempts runs vfox with args, and runs it again when it times out, up to
// networkAttempts times in all. Any other result is returned at once.
func (h *harness) vfoxAttempts(t *testing.T, args ...string) outcome {
	t.Helper()
	for attempt := 1; ; attempt++ {
		o := h.vfoxOutcome(t, args...)
		if !timedOut(o) || attempt == networkAttempts {
			return o
		}
		t.Logf("vfox %s timed out, trying again (attempt %d of %d)", strings.Join(args, " "), attempt+1, networkAttempts)
		time.Sleep(time.Duration(attempt) * 5 * time.Second)
	}
}

// vfox runs vfox with args, and stops the test when it fails. It returns the
// output on both streams.
func (h *harness) vfox(t *testing.T, args ...string) string {
	t.Helper()
	o := h.vfoxAttempts(t, args...)
	if o.code != 0 {
		t.Fatalf("vfox %s exited with code %d\n--- stdout ---\n%s\n--- stderr ---\n%s",
			strings.Join(args, " "), o.code, o.stdout, o.stderr)
	}
	return o.combined()
}

// expectVfoxFails checks that vfox fails with args, and that its output says needle.
func (h *harness) expectVfoxFails(t *testing.T, label, needle string, args ...string) {
	t.Helper()
	o := h.vfoxAttempts(t, args...)
	if o.code == 0 {
		t.Fatalf("%s: vfox %s should have failed:\n%s", label, strings.Join(args, " "), o.combined())
	}
	expectContains(t, label, o.combined(), needle)
}

// useGlobal makes spec the global zig.
func (h *harness) useGlobal(t *testing.T, spec string) {
	t.Helper()
	h.vfox(t, "use", "--global", spec)
}

// expectContains checks that text contains needle, and logs the check as passed.
func expectContains(t *testing.T, label, text, needle string) {
	t.Helper()
	if !strings.Contains(text, needle) {
		t.Fatalf("%s: expected to find %q in the output:\n%s", label, needle, text)
	}
	t.Logf("PASS %s", label)
}

// zipPlugin writes the parts of the checkout that the plugin runs from into a zip
// archive, which vfox add --source reads.
func (h *harness) zipPlugin(t *testing.T, dest string) {
	t.Helper()
	file, err := os.Create(dest)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	w := zip.NewWriter(file)
	for _, part := range []string{"metadata.lua", "hooks", "lib"} {
		err := filepath.WalkDir(filepath.Join(h.repo, part), func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			name, err := filepath.Rel(h.repo, path)
			if err != nil {
				return err
			}
			name = filepath.ToSlash(name)
			if d.IsDir() {
				_, err := w.Create(name + "/")
				return err
			}
			return addFile(w, name, path)
		})
		if err != nil {
			t.Fatal(err)
		}
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
}

// addFile adds the file at path to the archive under name.
func addFile(w *zip.Writer, name, path string) error {
	src, err := os.Open(path)
	if err != nil {
		return err
	}
	defer src.Close()
	entry, err := w.Create(name)
	if err != nil {
		return err
	}
	_, err = io.Copy(entry, src)
	return err
}

// download fetches url into dest. A failed attempt is tried again, three
// attempts in all.
func download(t *testing.T, url, dest string) {
	t.Helper()
	var err error
	for attempt := 1; attempt <= 3; attempt++ {
		if err = fetch(url, dest); err == nil {
			return
		}
		if attempt < 3 {
			time.Sleep(time.Duration(attempt) * 2 * time.Second)
		}
	}
	t.Fatalf("download %s: %v", url, err)
}

// fetch writes the body of a GET request for url to dest.
func fetch(url, dest string) error {
	client := &http.Client{Timeout: 10 * time.Minute}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP status %s", resp.Status)
	}
	file, err := os.Create(dest)
	if err != nil {
		return err
	}
	if _, err := io.Copy(file, resp.Body); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}

// fileSHA256 returns the lower-case hex SHA-256 digest of the file at path.
func fileSHA256(t *testing.T, path string) string {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	sum := sha256.New()
	if _, err := io.Copy(sum, file); err != nil {
		t.Fatal(err)
	}
	return hex.EncodeToString(sum.Sum(nil))
}

var versionPattern = regexp.MustCompile(`\d+\.\d+\.\d+`)

// versionIn returns the first x.y.z number in text, or "" when there is none.
func versionIn(text string) string {
	return versionPattern.FindString(text)
}

// latestRelease returns the release on the first line of the search output that
// names latest.
func latestRelease(search string) string {
	for _, line := range strings.Split(search, "\n") {
		if strings.Contains(line, "latest") {
			if v := versionIn(line); v != "" {
				return v
			}
		}
	}
	return ""
}

// compareVersions compares two x.y.z numbers. It returns a negative number when
// a is lower than b, zero when they are equal, and a positive one when a is higher.
func compareVersions(a, b string) int {
	x, y := parseVersion(a), parseVersion(b)
	for i := range x {
		if x[i] != y[i] {
			return x[i] - y[i]
		}
	}
	return 0
}

// parseVersion splits an x.y.z number into its three parts.
func parseVersion(v string) [3]int {
	var parts [3]int
	for i, field := range strings.SplitN(v, ".", 3) {
		parts[i], _ = strconv.Atoi(field)
	}
	return parts
}
