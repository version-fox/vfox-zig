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

-- The indexes as they were on 2026-11-21 (tests/fixtures/index/README.md). A
-- test lists an address in `failures` to make its request fail.
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
local plugin = test.load({
    os = "linux",
    arch = "amd64",
    http = function(request)
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

local function listing()
    return plugin:Available({})
end

local function position(list, version)
    for i, item in ipairs(list) do
        if item.version == version then
            return i, item
        end
    end
    error("version not listed: " .. version)
end

local function count_notes(list, note)
    local count = 0
    for _, item in ipairs(list) do
        if item.note == note then
            count = count + 1
        end
    end
    return count
end

local list = listing()

-- The newest official release is the one marked latest, not the newest one
-- whose index entry carries a version field (0.17.1 does; 0.15.1 once did not).
local _, latest = position(list, "0.17.1")
assert(latest.note == "latest", "0.17.1 is latest, got note " .. latest.note)
assert(count_notes(list, "latest") == 1, "exactly one release is latest")
local _, older = position(list, "0.17.0")
assert(older.note == "", "a release without a name has an empty note, got " .. older.note)

-- Ziglang's master is the nightly, and no other build is.
local _, nightly = position(list, "0.18.0-dev.1260+833623422")
assert(nightly.note == "nightly", "master is the nightly, got " .. nightly.note)
assert(count_notes(list, "nightly") == 1, "only one build is the nightly")

-- Mach names are the notes of their builds, several to a version, in key order.
local _, mach_latest = position(list, "0.18.0-dev.935+ead8f5a7a")
assert(mach_latest.note == "2026.10.22-mach, mach-latest", "mach names, got " .. mach_latest.note)
local _, mach_2024 = position(list, "0.14.0-dev.2577+271452d22")
assert(mach_2024.note == "2024.11.0-mach", "the Mach master is not listed as nightly, got " .. mach_2024.note)
local _, mach_old = position(list, "0.13.0-dev.351+64ef45eb0")
assert(mach_old.note == "0.4.0-mach, 2024.5.0-mach", "shared version, got " .. mach_old.note)

-- Every note is a list of names separated by commas, never the pipe the old code joined with.
for _, item in ipairs(list) do
    assert(not item.note:find("|", 1, true), "no pipe-joined notes: " .. item.version .. " " .. item.note)
end

-- Versions are listed once, newest first, and a pre-release sits below its release.
local seen = {}
for _, item in ipairs(list) do
    assert(not seen[item.version], "listed twice: " .. item.version)
    seen[item.version] = true
end
local release_position = position(list, "0.17.0")
local dev_position = position(list, "0.17.0-dev.2228+955228b68")
assert(release_position < dev_position, "0.17.0 comes before its development build 0.17.0-dev.2228")
assert(position(list, "0.17.1") < release_position, "0.17.1 comes before 0.17.0")
assert(position(list, "0.14.0") < position(list, "0.14.0-dev.2577+271452d22"), "0.14.0 comes before 0.14.0-dev.2577")

-- vfox takes the first entry as the latest for `zig@latest`, so it must be the
-- newest official release, with every development build listed after the releases.
assert(list[1].version == "0.17.1", "the first entry is the latest release, got " .. list[1].version)
local last_release, first_development = nil, nil
for i, item in ipairs(list) do
    if item.version:find("-", 1, true) then
        first_development = first_development or i
    else
        last_release = i
    end
end
assert(last_release < first_development, "every release is listed before the development builds")

-- The listing is the same on every call.
local again = listing()
assert(#again == #list, "same number of versions on a second call")
for i, item in ipairs(list) do
    assert(again[i].version == item.version and again[i].note == item.note, "same order and notes on a second call")
end

-- Mach's index is optional: when it cannot be read, the official releases are
-- still listed, with a warning that names what failed. The warning goes to
-- standard error, and nothing is printed to standard output, where the list is.
local warnings = {}
local printed = {}
local original_stderr = io.stderr
local original_print = print
print = function(...)
    table.insert(printed, table.concat({ ... }, " "))
end
io.stderr = {
    write = function(_, ...)
        table.insert(warnings, table.concat({ ... }))
    end,
}
failures[MACH_URL] = true
local official = listing()
failures[MACH_URL] = nil
io.stderr = original_stderr
print = original_print
assert(#printed == 0, "nothing is printed to standard output: " .. table.concat(printed, "; "))
assert(#warnings == 1, "one warning when Mach cannot be read, got " .. #warnings)
assert(warnings[1]:sub(-1) == "\n", "the warning is a line of its own: " .. warnings[1])
local warning = warnings[1]:sub(1, -2)
-- vfox wraps the transport's error, so the test matches its parts, not the whole text.
assert(
    warning:find("WARNING: cannot download " .. MACH_URL .. ":", 1, true) == 1,
    "the warning names the Mach index: " .. warning
)
assert(warning:find("connection refused", 1, true), "the warning gives the reason: " .. warning)
assert(warning:find("; listing the official releases only$"), "the warning says what is listed: " .. warning)
position(official, "0.17.1")
for _, item in ipairs(official) do
    assert(not item.note:find("mach", 1, true), "no Mach name without the Mach index: " .. item.note)
end
assert(not pcall(position, official, "0.18.0-dev.935+ead8f5a7a"), "no Mach development build without the Mach index")

-- Ziglang's index is required: without it there is nothing to list, and the
-- error says which index and why.
failures[ZIG_URL] = true
local ok, err = pcall(plugin.Available, plugin, {})
failures[ZIG_URL] = nil
assert(not ok, "Available fails without the Ziglang index")
assert(
    tostring(err):find("cannot download " .. ZIG_URL .. ":", 1, true),
    "the error names the index: " .. tostring(err)
)
assert(tostring(err):find("connection refused", 1, true), "the error gives the reason: " .. tostring(err))

-- Another platform is listed from the same indexes: Windows on arm64 gets the zip.
RUNTIME.osType = "windows"
RUNTIME.archType = "arm64"
local windows = listing()
local _, windows_latest = position(windows, "0.17.1")
assert(windows_latest.note == "latest", "Windows arm64 has 0.17.1 as latest")
RUNTIME.osType = "linux"
RUNTIME.archType = "amd64"

print("available tests passed")
