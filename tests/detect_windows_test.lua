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
    os = "windows",
    arch = "amd64",
    env = {
        USERPROFILE = "C:\\Users\\u",
        ProgramFiles = "C:\\Program Files",
        VFOX_HOME = "D:\\VFox\\",
        PATH = "C:\\Tools;C:\\Users\\u\\scoop\\shims;C:\\Users\\u\\.vfox\\cache\\zig\\v-0.12.0;C:\\Zig;C:\\Program Files (x86)\\Zig;D:\\vfox\\bin;D:\\vfox-tools",
    },
})

-- The same fake file system as detect_test.lua, keyed by forward slashes.
local files = {}
local children = {}
local versions = {}
-- Every command the detection runs, as cmd.exe receives it.
local commands = {}

local function norm(path)
    return (path:gsub("\\", "/"))
end

local function add_zig(dir, version)
    files[norm(dir .. "\\zig.exe")] = true
    files[norm(dir .. "\\lib\\std\\std.zig")] = true
    versions[norm(dir .. "\\zig.exe")] = version
end

local function answer(command)
    table.insert(commands, command)
    local dir = command:match('^dir /b "(.-)" 2>nul$')
    if dir then
        return children[norm(dir)] or {}
    end
    -- cmd.exe strips the outer pair of quotes, which the detection adds so
    -- that a path with parentheses still runs.
    local binary = command:match('^""(.-)" version 2>nul"$')
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

-- The handle has read and close only, as vfox's io.popen on Windows does, and
-- the output has CRLF line ends as cmd.exe writes it.
io.popen = function(command)
    local output = table.concat(answer(command), "\r\n")
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

-- On PATH: C:\Tools has a zig with its library; the shim and vfox's own install do not count.
add_zig("C:\\Tools", "0.13.0")
add_zig("C:\\Users\\u\\scoop\\shims", "0.11.5")
add_zig("C:\\Users\\u\\.vfox\\cache\\zig\\v-0.12.0", "0.12.0")
-- Zig 0.14 development build on PATH.
add_zig("C:\\Zig", "0.14.0-dev.1+abc123")
-- A zig in a directory whose name has parentheses, which cmd.exe reads specially.
add_zig("C:\\Program Files (x86)\\Zig", "0.9.0")
-- VFOX_HOME is written with a trailing separator and in capitals. Its directories
-- are vfox's, and a directory that only starts with the same letters is not.
add_zig("D:\\vfox\\bin", "0.16.0")
add_zig("D:\\vfox-tools", "0.15.0")

-- Scoop: current and a version folder hold the same zig; the first listed wins.
children[norm("C:\\Users\\u\\scoop\\apps\\zig")] = { "0.11.0", "current" }
add_zig("C:\\Users\\u\\scoop\\apps\\zig\\0.11.0", "0.11.0")
add_zig("C:\\Users\\u\\scoop\\apps\\zig\\current", "0.11.0")

-- A system directory from an installer.
add_zig("C:\\Program Files\\zig", "0.10.0")

local found = plugin:Detect({})
local lines = {}
for _, item in ipairs(found) do
    table.insert(lines, item.version .. " " .. item.path .. " (" .. item.note .. ")")
end
local expected = {
    "0.9.0 C:\\Program Files (x86)\\Zig (on PATH)",
    "0.10.0 C:\\Program Files\\zig (system directory)",
    "0.11.0 C:\\Users\\u\\scoop\\apps\\zig\\0.11.0 (installed by Scoop)",
    "0.13.0 C:\\Tools (on PATH)",
    "0.14.0-dev.1+abc123 C:\\Zig (on PATH)",
    "0.15.0 D:\\vfox-tools (on PATH)",
}
assert(
    #lines == #expected,
    "expected " .. #expected .. " installations, got " .. #lines .. ":\n" .. table.concat(lines, "\n")
)
for i, line in ipairs(expected) do
    assert(lines[i] == line, ("installation %d: expected %s, got %s"):format(i, line, lines[i]))
end

-- The version of the zig in the parenthesized directory is asked with the outer
-- pair of quotes that cmd.exe strips.
local wanted = '""C:\\Program Files (x86)\\Zig\\zig.exe" version 2>nul"'
local asked = false
for _, command in ipairs(commands) do
    if command == wanted then
        asked = true
    end
end
assert(asked, "the version command of the parenthesized zig, got none matching: " .. wanted)

print("detect windows tests passed")
