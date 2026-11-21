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

local util = require("util")

--- Finds zig installations that are already on the machine, for `vfox link --detect zig`.
--- A zig is reported when its executable runs, `zig version` names it, and its
--- `lib/std` sits beside it, which is the layout vfox links: the directory is
--- the one holding the executable, so PATH reaches it and zig finds its library.
local detect = {}

local function is_windows()
    return RUNTIME ~= nil and RUNTIME.osType == "windows"
end

local function executable()
    if is_windows() then
        return "zig.exe"
    end
    return "zig"
end

--- Joins path segments with the platform separator.
function detect.join(...)
    local separator = is_windows() and "\\" or "/"
    local result = nil
    for _, part in ipairs({ ... }) do
        if result == nil then
            result = part
        else
            local last = result:sub(-1)
            if last == "/" or last == "\\" then
                result = result .. part
            else
                result = result .. separator .. part
            end
        end
    end
    result = result or ""
    if is_windows() then
        result = (result:gsub("/", "\\"))
    end
    return result
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Quotes a value for the shell the commands below run in.
local function quote(value)
    if is_windows() then
        return '"' .. (value:gsub('"', '""')) .. '"'
    end
    return "'" .. (value:gsub("'", "'\\''")) .. "'"
end

--- Runs a command and returns its output lines, or {} when it cannot run. The
--- output is read with read("*a"): vfox's io.popen on Windows returns a handle
--- that has read and close, and no lines, so handle:lines() fails there.
local function lines_of(command)
    local handle = io.popen(command, "r")
    if not handle then
        return {}
    end
    local output = handle:read("*a") or ""
    handle:close()
    local lines = {}
    for line in output:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    return lines
end

local function exists(path)
    local file = io.open(path, "r")
    if file == nil then
        return false
    end
    file:close()
    return true
end

--- Lists the entries of a directory as full paths, or {} when it cannot be read.
--- @param dir string
--- @return table
function detect.list_children(dir)
    if dir == "" then
        return {}
    end
    local command
    if is_windows() then
        command = "dir /b " .. quote(dir) .. " 2>nul"
    else
        command = "ls -1 " .. quote(dir) .. " 2>/dev/null"
    end
    local children = {}
    for _, line in ipairs(lines_of(command)) do
        local name = trim(line)
        if name ~= "" and name ~= "." and name ~= ".." then
            table.insert(children, detect.join(dir, name))
        end
    end
    return children
end

--- The command line that prints the version of an executable. On Windows the line
--- runs in cmd.exe, which strips one pair of quotes around the whole line when the
--- line starts with a quote and holds more than two quotes. Wrapping the quoted
--- path in one more pair makes that happen, so a path with spaces or parentheses
--- (Program Files (x86)) still runs.
local function version_command(executable_path)
    if is_windows() then
        return '"' .. quote(executable_path) .. ' version 2>nul"'
    end
    return quote(executable_path) .. " version 2>/dev/null"
end

--- Returns the version that `zig version` prints for an executable, or nil.
local function version_of(executable_path)
    for _, line in ipairs(lines_of(version_command(executable_path))) do
        local version = trim(line)
        -- Release and development builds: 0.13.0, 0.14.0-dev.2577+271452d22.
        if version:match("^%d[%w%.%+%-]*$") then
            return version
        end
    end
    return nil
end

--- Follows symbolic links, so that /usr/bin/zig names the directory the binary is really in.
local function real_path(path)
    if is_windows() then
        return path
    end
    local lines = lines_of("readlink -f " .. quote(path) .. " 2>/dev/null")
    local target = lines[1] and trim(lines[1]) or ""
    if target == "" then
        return path
    end
    return target
end

--- Returns the directory that holds a path.
local function parent(path)
    local dir = path:match("^(.*)[/\\][^/\\]*$")
    if dir == nil or dir == "" then
        return path
    end
    return dir
end

--- Whether a directory must not be linked: the installs vfox manages, and the
--- shim directories of version managers. A shim runs whichever version the
--- manager has selected, not the one that sits beside it.
local function skipped(dir)
    local lower = dir:lower()
    if lower:find("[/\\]%.vfox[/\\]") then
        return true
    end
    if lower:match("[/\\]shims$") or lower:find("[/\\]shims[/\\]") then
        return true
    end
    return lower:match("chocolatey[/\\]bin$") ~= nil
end

--- Returns the directories of PATH that are absolute, without quotes.
local function path_dirs()
    local value = os.getenv("PATH") or ""
    local separator = is_windows() and ";" or ":"
    local dirs = {}
    for entry in (value .. separator):gmatch("(.-)" .. separator) do
        local dir = trim((entry:gsub('"', "")))
        local absolute = dir:sub(1, 1) == "/" or dir:match("^%a:[/\\]") ~= nil or dir:sub(1, 2) == "\\\\"
        if absolute and not skipped(dir) then
            table.insert(dirs, dir)
        end
    end
    return dirs
end

--- Adds the zig in dir to found, unless its directory was seen already.
local function consider(dir, note, found, seen)
    if dir == "" or skipped(dir) then
        return
    end
    local exe = detect.join(dir, executable())
    if not exists(exe) then
        return
    end
    local binary = real_path(exe)
    local home = parent(binary)
    if seen[home] or skipped(home) then
        return
    end
    seen[home] = true
    if not exists(detect.join(home, "lib", "std", "std.zig")) then
        return
    end
    local version = version_of(binary)
    if version ~= nil then
        table.insert(found, {
            version = version,
            path = home,
            note = note,
        })
    end
end

--- The places beyond PATH that hold zig installs, with the note that names
--- each. depth counts the levels below the directory to look at: a version
--- manager keeps a directory per version, and some keep one more inside it.
local function roots()
    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
    local list = {}
    local function add(path, note, depth)
        if path ~= nil and path ~= "" then
            table.insert(list, {
                path = path,
                note = note,
                depth = depth,
            })
        end
    end

    if is_windows() then
        local profile = os.getenv("USERPROFILE") or home
        local program_files = os.getenv("ProgramFiles") or "C:\\Program Files"
        add(detect.join(profile, "scoop", "apps", "zig"), "installed by Scoop", 1)
        add(detect.join(profile, ".zvm"), "installed by zvm", 1)
        add(detect.join(profile, ".local", "share", "mise", "installs", "zig"), "installed by mise", 2)
        add(detect.join(program_files, "zig"), "system directory", 1)
    else
        add(detect.join(home, ".local", "share", "mise", "installs", "zig"), "installed by mise", 2)
        add(detect.join(home, ".asdf", "installs", "zig"), "installed by asdf", 2)
        add(detect.join(home, ".zvm"), "installed by zvm", 1)
        add("/usr/local", "system directory", 1)
        add("/opt", "system directory", 1)
        add("/usr/lib", "system directory", 1)
    end
    return list
end

--- Finds every zig on the machine. Where two entries name the same version the
--- first one found wins, and PATH comes first, so the zig a shell runs is the one
--- reported. The result is sorted by version, then by path.
--- @return table list of { version, path, note }
function detect.find_all()
    local found = {}
    local seen = {}

    for _, dir in ipairs(path_dirs()) do
        consider(dir, "on PATH", found, seen)
    end
    for _, root in ipairs(roots()) do
        local function visit(dir, level)
            consider(dir, root.note, found, seen)
            if level < root.depth then
                for _, child in ipairs(detect.list_children(dir)) do
                    visit(child, level + 1)
                end
            end
        end
        visit(root.path, 0)
    end

    local result = {}
    local versions = {}
    for _, item in ipairs(found) do
        if not versions[item.version] then
            versions[item.version] = true
            table.insert(result, item)
        end
    end
    table.sort(result, function(a, b)
        local order = util.compare_versions(a.version, b.version)
        if order ~= 0 then
            return order < 0
        end
        return a.path < b.path
    end)
    return result
end

return detect
