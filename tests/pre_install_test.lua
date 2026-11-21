-- Copyright 2026 Han Li and contributors
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--   http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local test = require("vfox.test")

local ZIG_URL = "https://ziglang.org/download/index.json"
local MACH_URL = "https://machengine.org/zig/index.json"

local function read_fixture(name)
    local file = assert(io.open(RUNTIME.pluginDirPath .. "/tests/fixtures/index/" .. name))
    local content = file:read("*a")
    file:close()
    return content
end

-- Read on the first request: RUNTIME, which read_fixture needs, exists once test.load has run.
local answers = nil
local function answer_for(url)
    if answers == nil then
        answers = {
            [ZIG_URL] = read_fixture("ziglang.json"),
            [MACH_URL] = read_fixture("mach.json"),
        }
    end
    return answers[url]
end

local failures = {}
-- Addresses whose HEAD request gets a 404, as ziglang.org answers for a pruned build.
local gone = {}
local plugin = test.load({
    os = "linux",
    arch = "amd64",
    http = function(request)
        if request.method == "HEAD" then
            return {
                status_code = gone[request.url] and 404 or 200,
            }
        end
        if failures[request.url] then
            return nil, "connection refused"
        end
        local body = answer_for(request.url)
        assert(body ~= nil, "unexpected request: " .. request.url)
        return {
            status_code = 200,
            body = body,
        }
    end,
})

local function install(version)
    return plugin:PreInstall({ version = version })
end

local function fails_with(version, expected)
    local ok, err = pcall(install, version)
    assert(not ok, "PreInstall(" .. version .. ") should fail")
    assert(
        tostring(err):find(expected, 1, true),
        "error for " .. version .. " should mention: " .. expected .. "; got: " .. tostring(err)
    )
end

-- A plain release: its name, URL and SHA-256 come from the index, and it has no name.
local release = install("0.13.0")
assert(release.version == "0.13.0", "version " .. tostring(release.version))
assert(release.url == "https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz", "url " .. release.url)
assert(
    release.sha256 == "d45312e61ebcc48032b77bc4cf7fd6915c11fa16e4aad116b66c9468211230ea",
    "sha256 " .. release.sha256
)
assert(release.note == "", "no note for 0.13.0")

-- latest names the newest official release.
local latest = install("latest")
assert(latest.version == "0.17.1", "latest installs 0.17.1, got " .. latest.version)
assert(latest.url == "https://ziglang.org/download/0.17.1/zig-x86_64-linux-0.17.1.tar.xz", "latest url " .. latest.url)
assert(latest.sha256 == "3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a", "latest sha256")
assert(latest.note == "latest", "latest note " .. latest.note)

-- nightly is Ziglang's master.
local nightly = install("nightly")
assert(nightly.version == "0.18.0-dev.1260+833623422", "nightly version " .. nightly.version)
assert(nightly.note == "nightly", "nightly note " .. nightly.note)

-- ziglang.org has pruned this Mach build (its download is a 404), so the index's
-- other address for it, on Mach's package host, is the one installed. The URL is
-- the same on every call, although the index is read in no fixed order.
local MACH_ZIG_URL = "https://ziglang.org/builds/zig-linux-x86_64-0.14.0-dev.2577+271452d22.tar.xz"
local MACH_HOST_URL = "https://pkg.hexops.org/zig/zig-linux-x86_64-0.14.0-dev.2577+271452d22.tar.xz"
gone[MACH_ZIG_URL] = true
for i = 1, 5 do
    local mach = install("2024.11.0-mach")
    assert(mach.version == "0.14.0-dev.2577+271452d22", "mach version " .. mach.version)
    assert(mach.url == MACH_HOST_URL, "mach url on call " .. i .. ": " .. tostring(mach.url))
    assert(mach.sha256 == "7be6abdebfa970c6138d165b348d0464e84f16f531e71cb20c0e052fae1d8c8d", "mach sha256")
    assert(mach.note == "2024.11.0-mach", "mach note must not carry nightly, got " .. mach.note)
end
-- Where ziglang.org still has the build, its address is the download.
gone[MACH_ZIG_URL] = nil
assert(install("2024.11.0-mach").url == MACH_ZIG_URL, "a reachable ziglang.org address is used first")
gone[MACH_ZIG_URL] = true

-- A name a build has is one of the notes; a build installs by its version as well.
local by_version = install("0.14.0-dev.2577+271452d22")
assert(by_version.url == MACH_HOST_URL, "install by version")
assert(by_version.note == "2024.11.0-mach", "the note still names the Mach build")
gone[MACH_ZIG_URL] = nil

local mach_latest = install("mach-latest")
assert(mach_latest.version == "0.18.0-dev.935+ead8f5a7a", "mach-latest version " .. mach_latest.version)
assert(mach_latest.note == "2026.10.22-mach, mach-latest", "mach-latest note " .. mach_latest.note)
assert(mach_latest.url:find("^https://ziglang%.org/builds/") ~= nil, "mach-latest downloads from ziglang.org")

-- Windows on arm64 gets the zip of the same release.
RUNTIME.osType = "windows"
RUNTIME.archType = "arm64"
local windows = install("0.17.1")
assert(
    windows.url:match("zig%-aarch64%-windows%-0%.17%.1%.zip$") ~= nil,
    "windows arm64 url should be the zip: " .. windows.url
)
RUNTIME.osType = "linux"
RUNTIME.archType = "amd64"

-- Errors say what was asked for and where it was looked for.
fails_with("9.9.9", "zig 9.9.9 is not listed for linux/amd64")
fails_with("", "No version given")

-- Mach's index is optional for installs of the official releases.
failures[MACH_URL] = true
assert(install("0.13.0").version == "0.13.0", "an official release installs without the Mach index")
fails_with("2024.11.0-mach", "zig 2024.11.0-mach is not listed")
failures[MACH_URL] = nil

print("pre_install tests passed")
