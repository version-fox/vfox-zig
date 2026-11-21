#!/usr/bin/env bash
# Copyright 2026 Han Li and contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# End-to-end checks of this plugin with a real vfox on Linux. The plugin is
# registered from the checkout the script runs in, so a change is tested as it
# stands. It needs vfox 1.1.0 or later (link --detect), zip, curl, sha256sum,
# tar with xz, and network access to ziglang.org and machengine.org.
#
# Run it from the repository root on a Linux host, or in a throwaway container
# (tests/e2e/linux/Dockerfile):
#   bash tests/e2e/linux/e2e.sh
#   docker build -t zig-e2e tests/e2e/linux
#   docker run --rm -v "$PWD:/src:ro" zig-e2e

set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
readonly REPO

# The Mach build used below, and the zig installed as a system copy, with the
# SHA-256 that ziglang.org's index lists for its archive (tests/fixtures/index).
readonly MACH_NAME="2024.11.0-mach"
readonly MACH_VERSION="0.14.0-dev.2577+271452d22"
readonly SYSTEM_VERSION="0.12.1"
readonly SYSTEM_URL="https://ziglang.org/download/0.12.1/zig-linux-x86_64-0.12.1.tar.xz"
readonly SYSTEM_SHA256="8860fc9725c2d9297a63008f853e9b11e3c5a2441217f99c1e3104cc6fa4a443"

WORK="$(mktemp -d)"
readonly WORK
cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT

# A private home for vfox, so the run never touches the real one. vfox keeps its
# user and shared directories under $HOME/.vfox, which is a directory named .vfox
# as the default is, so the installs made here are not taken for system installs.
unset VFOX_HOME
export HOME="$WORK/home"
mkdir -p "$HOME"

step() {
    printf '\n== %s\n' "$1"
}

pass() {
    printf 'PASS %s\n' "$1"
}

die() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

# run LOG COMMAND...: runs COMMAND with its output in $WORK/LOG. When COMMAND
# fails, the script stops and shows that output.
run() {
    local log="$WORK/$1"
    shift
    if ! "$@" >"$log" 2>&1; then
        cat "$log" >&2
        die "$* failed"
    fi
}

# expect_contains LABEL TEXT NEEDLE: passes when TEXT contains NEEDLE.
expect_contains() {
    if ! grep -qF -- "$3" <<<"$2"; then
        printf '%s\n' "--- output ---" "$2" >&2
        die "$1: expected to find: $3"
    fi
    pass "$1"
}

# expect_fails LABEL NEEDLE COMMAND...: passes when COMMAND fails and says NEEDLE.
expect_fails() {
    local label="$1" needle="$2" output code
    shift 2
    set +e
    output="$("$@" 2>&1)"
    code=$?
    set -e
    if [[ $code -eq 0 ]]; then
        printf '%s\n' "--- output ---" "$output" >&2
        die "$label: the command should have failed"
    fi
    expect_contains "$label" "$output" "$needle"
}

# use_zig SPEC makes SPEC the global zig. Then it refreshes PATH the way the
# shell hook does between prompts, which a script does not get.
use_zig() {
    run use.log vfox use --global "$1"
    eval "$(vfox env -s bash)"
}

check_vfox() {
    local found lowest
    found="$(vfox --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
    lowest="$(printf '%s\n' 1.1.0 "$found" | sort -V | head -n 1)"
    if [[ -z "$found" || "$lowest" != "1.1.0" ]]; then
        die "vfox 1.1.0 or later is needed for link --detect, found: ${found:-none}"
    fi
    pass "vfox $found is 1.1.0 or later"
    # vfox use needs the shell hook set up first, as an interactive shell has it.
    eval "$(vfox activate bash)"
}

add_plugin() {
    step "register the plugin from this checkout"
    (cd "$REPO" && zip -qr "$WORK/zig.zip" metadata.lua hooks lib)
    run add.log vfox add zig --source "$WORK/zig.zip"
    pass "vfox add zig --source <the checkout>"
    # The notes printed by vfox info point to the README, which lists the names.
    run info.log vfox info zig
    expect_contains "vfox info zig points to the README" "$(cat "$WORK/info.log")" "README.md"
}

check_search() {
    step "vfox search zig"
    run search.log vfox search zig
    local output
    output="$(cat "$WORK/search.log")"
    expect_contains "the search lists 0.13.0" "$output" "0.13.0"
    expect_contains "the search names the nightly" "$output" "nightly"
    expect_contains "the search names a Mach build" "$output" "$MACH_NAME"
    expect_contains "the search marks a release as latest" "$output" "latest"
}

install_pinned() {
    step "install a pinned release"
    run install-0.13.0.log vfox install zig@0.13.0
    # vfox prints this only when the download has a checksum to compare with.
    expect_contains "the download is verified against its checksum" "$(cat "$WORK/install-0.13.0.log")" "Verifying checksum"
    use_zig zig@0.13.0
    expect_contains "zig 0.13.0 is on PATH" "$(zig version 2>&1)" "0.13.0"
}

check_compile() {
    step "the standard library is found from the installed zig"
    cat >"$WORK/hello.zig" <<'EOF'
const std = @import("std");

pub fn main() void {
    std.debug.print("hello from zig\n", .{});
}
EOF
    expect_contains "zig run compiles against the std library" "$(cd "$WORK" && zig run hello.zig 2>&1)" "hello from zig"
}

install_latest() {
    step "install latest"
    run install-latest.log vfox install zig@latest
    # The release that search marks latest is the one that installs.
    local expected
    expected="$(awk '/latest/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }' "$WORK/search.log")"
    if [[ -z "$expected" ]]; then
        die "the search output names no release as latest"
    fi
    pass "search marks $expected as latest"
    # use maps the name latest to the installed version it names.
    use_zig zig@latest
    expect_contains "zig@latest selects the release search marks latest" "$(zig version 2>&1)" "$expected"
}

install_mach() {
    step "install a Mach build by its name"
    run install-mach.log vfox install "zig@$MACH_NAME"
    use_zig "zig@$MACH_NAME"
    expect_contains "zig@$MACH_NAME selects the Mach build" "$(zig version 2>&1)" "$MACH_VERSION"
}

check_missing() {
    step "a version the index does not list fails"
    expect_fails "vfox install zig@9.9.9 fails" "is not listed for linux/amd64" vfox install zig@9.9.9
}

check_system_zig() {
    step "a zig that vfox did not install is linked with link --detect"
    local system_dir="$WORK/system/zig-linux-x86_64-$SYSTEM_VERSION"
    mkdir -p "$WORK/system"
    run system-download.log curl --fail --silent --show-error --location --retry 3 --output "$WORK/system.tar.xz" "$SYSTEM_URL"
    if ! echo "$SYSTEM_SHA256  $WORK/system.tar.xz" | sha256sum --check --status; then
        die "the zig $SYSTEM_VERSION archive does not match its checksum"
    fi
    run system-unpack.log tar --extract --xz --file "$WORK/system.tar.xz" --directory "$WORK/system"
    pass "unpacked zig $SYSTEM_VERSION as a system copy"

    # The copy is only on PATH, which is where link --detect looks first.
    export PATH="$system_dir:$PATH"
    run detect.log vfox link --detect -y zig
    expect_contains "link --detect finds the copy on PATH" "$(cat "$WORK/detect.log")" "$system_dir"
    expect_contains "link --detect names the version" "$(cat "$WORK/detect.log")" "$SYSTEM_VERSION"

    run list.log vfox list zig
    expect_contains "vfox list shows the link" "$(cat "$WORK/list.log")" "$system_dir"

    use_zig "zig@$SYSTEM_VERSION"
    expect_contains "the linked zig runs" "$(zig version 2>&1)" "$SYSTEM_VERSION"

    # Versions vfox installed are not offered again, so a second run finds nothing new.
    run detect-again.log vfox link --detect -y zig
    expect_contains "a second link --detect finds nothing new" "$(cat "$WORK/detect-again.log")" "No new zig installations found"

    # Removing the link leaves the directory where it was.
    run uninstall.log vfox uninstall "zig@$SYSTEM_VERSION"
    if [[ ! -x "$system_dir/zig" ]]; then
        die "uninstalling a link removed the system zig"
    fi
    pass "vfox uninstall removes the link and keeps the system zig"
}

check_vfox
add_plugin
check_search
install_pinned
check_compile
install_latest
install_mach
check_missing
check_system_zig

step "all checks passed"
