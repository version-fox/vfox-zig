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
local plugin = test.load({
    os = "linux",
    arch = "amd64",
    env = {
        HOME = "/home/u",
        VFOX_HOME = "/srv/vfox",
        PATH = "/usr/bin:/home/u/bin:/home/u/.asdf/shims:/home/u/.vfox/cache/zig/v-0.12.1/bin:/srv/vfox/bin:/srv/VFox/bin:/srv/vfox-tools:/tmp/other/cache/zig/v-0.14.1/zig-0.14.1:relative/bin",
    },
})

-- A fake file system: files holds the paths that exist, children what a
-- directory lists, links what `readlink -f` answers, and versions what
-- `zig version` prints for a binary. Every key is normalized to forward slashes.
local files = {}
local children = {}
local links = {}
local versions = {}

local function norm(path)
    return (path:gsub("\\", "/"))
end

local function add_zig(dir, version, with_lib)
    files[norm(dir .. "/zig")] = true
    if with_lib ~= false then
        files[norm(dir .. "/lib/std/std.zig")] = true
    end
    if version ~= nil then
        versions[norm(dir .. "/zig")] = version
    end
end

-- Answers each command the detection runs, as the shell would.
local function answer(command)
    local dir = command:match("^ls %-1 '(.-)' 2>/dev/null$")
    if dir then
        return children[norm(dir)] or {}
    end
    local path = command:match("^readlink %-f '(.-)' 2>/dev/null$")
    if path then
        return { links[norm(path)] or path }
    end
    local binary = command:match("^'(.-)' version 2>/dev/null$")
    if binary then
        local version = versions[norm(binary)]
        return version and { version } or {}
    end
    error("unexpected command: " .. command)
end

io.open = function(path, mode)
    if (mode or "r") == "r" and files[norm(path)] then
        return {
            read = function()
                return ""
            end,
            close = function()
                return true
            end,
        }
    end
    return nil
end

-- The handle has read and close only, as vfox's io.popen on Windows does. A
-- detection that calls handle:lines() fails here, as it would on Windows.
io.popen = function(command)
    local output = table.concat(answer(command), "\n")
    local delivered = false
    return {
        read = function(_, format)
            assert(format == "*a", 'only read("*a") is supported, got ' .. tostring(format))
            if delivered then
                return ""
            end
            delivered = true
            return output
        end,
        close = function()
            return 0
        end,
    }
end

-- On PATH: /usr/bin/zig is a link into /usr/lib/zig, which holds a zig with its library.
links[norm("/usr/bin/zig")] = "/usr/lib/zig/zig"
add_zig("/usr/lib/zig", "0.13.0")
files[norm("/usr/bin/zig")] = true
-- A zig without its library cannot be linked: it would not find its std.
files[norm("/home/u/bin/zig")] = true
-- A version manager's shim runs whichever version is selected, so it is skipped.
add_zig("/home/u/.asdf/shims", "0.11.0")
-- vfox's own installs are never reported.
add_zig("/home/u/.vfox/cache/zig/v-0.12.1/bin", "0.12.1")
-- Relative PATH entries are not reported.
add_zig("relative/bin", "0.10.5")
-- A zig in VFOX_HOME is vfox's, whatever its layout.
add_zig("/srv/vfox/bin", "0.16.0")
-- vfox's install layout is recognized in any home, so a zig that vfox made under
-- another VFOX_HOME is not offered either.
add_zig("/tmp/other/cache/zig/v-0.14.1/zig-0.14.1", "0.14.1")
-- VFOX_HOME ends at a separator: a directory that only starts with its letters is not in it.
add_zig("/srv/vfox-tools", "0.15.0")
-- On Linux the file system is case-sensitive: a directory that differs from VFOX_HOME
-- only in letter case is another directory, so it is reported.
add_zig("/srv/VFox/bin", "0.15.1")

-- mise keeps a directory per version; a second level is searched too.
local mise = "/home/u/.local/share/mise/installs/zig"
children[norm(mise)] = { "0.14.0-dev.2577+271452d22", "0.9.1" }
add_zig(mise .. "/0.14.0-dev.2577+271452d22", "0.14.0-dev.2577+271452d22")
add_zig(mise .. "/0.9.1", "0.9.1")
-- The same version in a system directory is not listed twice: the first wins.
children["/usr/local"] = { "bin", "zig-x86_64-linux-0.10.0", "zig-x86_64-linux-0.9.1" }
add_zig("/usr/local/zig-x86_64-linux-0.10.0", "0.10.0")
add_zig("/usr/local/zig-x86_64-linux-0.9.1", "0.9.1")
-- A zig that does not run is skipped.
children["/opt"] = { "broken" }
add_zig("/opt/broken", nil)

local found = plugin:Detect({})
local lines = {}
for _, item in ipairs(found) do
    table.insert(lines, item.version .. " " .. item.path .. " (" .. item.note .. ")")
end
local expected = {
    "0.9.1 /home/u/.local/share/mise/installs/zig/0.9.1 (installed by mise)",
    "0.10.0 /usr/local/zig-x86_64-linux-0.10.0 (system directory)",
    "0.13.0 /usr/lib/zig (on PATH)",
    "0.14.0-dev.2577+271452d22 /home/u/.local/share/mise/installs/zig/0.14.0-dev.2577+271452d22 (installed by mise)",
    "0.15.0 /srv/vfox-tools (on PATH)",
    "0.15.1 /srv/VFox/bin (on PATH)",
}
assert(
    #lines == #expected,
    "expected " .. #expected .. " installations, got " .. #lines .. ":\n" .. table.concat(lines, "\n")
)
for i, line in ipairs(expected) do
    assert(lines[i] == line, ("installation %d: expected %s, got %s"):format(i, line, lines[i]))
end

-- macOS's file system ignores case by default, so there /srv/VFox/bin is the
-- directory of VFOX_HOME, and it is left out as it is on Windows.
local original_os = RUNTIME.osType
RUNTIME.osType = "darwin"
local on_macos = {}
for _, item in ipairs(plugin:Detect({})) do
    table.insert(on_macos, item.version .. " " .. item.path .. " (" .. item.note .. ")")
end
RUNTIME.osType = original_os
local without_variant = {}
for _, line in ipairs(expected) do
    if line ~= "0.15.1 /srv/VFox/bin (on PATH)" then
        table.insert(without_variant, line)
    end
end
for i = 1, math.max(#on_macos, #without_variant) do
    local want, got = without_variant[i], on_macos[i]
    assert(got == want, ("on macOS, installation %d: expected %s, got %s"):format(i, tostring(want), tostring(got)))
end

print("detect tests passed")
