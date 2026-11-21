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
local requests = 0
local plugin = test.load({
    os = "linux",
    arch = "amd64",
    http = function(request)
        requests = requests + 1
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

-- The installed versions, keyed by name the way vfox passes them.
local function installed(...)
    local map = {}
    for _, version in ipairs({ ... }) do
        map[version] = {
            name = "zig",
            version = version,
            path = "/sdks/zig-" .. version,
        }
    end
    return map
end

-- A name that is installed, or a number vfox matches itself, is answered
-- without reading the index.
local before = requests
assert(plugin:PreUse({ version = "0.13.0", installedSdks = installed("0.13.0", "0.17.1") }) == nil, "installed name")
assert(plugin:PreUse({ version = "0.13", installedSdks = installed("0.13.0") }) == nil, "dotted number")
assert(plugin:PreUse({ version = "0.14", installedSdks = installed("0.13.0") }) == nil, "not installed number")
assert(
    plugin:PreUse({ version = "0.14.0-dev.2577+271452d22", installedSdks = installed("0.14.0-dev.2577+271452d22") })
        == nil,
    "an installed development build"
)
assert(requests == before, "no index is read for those, got " .. (requests - before) .. " requests")

-- latest and nightly select the installed version they name, from the index.
local latest = plugin:PreUse({ version = "latest", installedSdks = installed("0.13.0", "0.17.1") })
assert(latest.version == "0.17.1", "latest selects 0.17.1, got " .. tostring(latest and latest.version))
assert(requests > before, "a name is looked up in the index")
assert(plugin:PreUse({ version = "latest", installedSdks = installed("0.13.0") }) == nil, "latest is not installed")

local nightly = plugin:PreUse({ version = "nightly", installedSdks = installed("0.18.0-dev.1260+833623422") })
assert(nightly.version == "0.18.0-dev.1260+833623422", "nightly selects its installed version")

-- A Mach name selects the build it names.
local mach = plugin:PreUse({ version = "2024.11.0-mach", installedSdks = installed("0.14.0-dev.2577+271452d22") })
assert(mach.version == "0.14.0-dev.2577+271452d22", "a Mach name selects its build")

-- When the index cannot be read, `use` leaves the name to vfox, with a warning.
local warnings = {}
local original_print = print
print = function(...)
    table.insert(warnings, table.concat({ ... }, " "))
end
failures[ZIG_URL] = true
local offline = plugin:PreUse({ version = "latest", installedSdks = installed("0.17.1") })
failures[ZIG_URL] = nil
print = original_print
assert(offline == nil, "no selection without the index")
assert(
    #warnings == 1 and warnings[1]:find("cannot resolve latest", 1, true),
    "a warning names the name: " .. tostring(warnings[1])
)

print("pre_use tests passed")
