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

local http = require("http")
local json = require("json")

local util = {}
util.BaseUrl = "https://ziglang.org/download/index.json"
util.MachUrl = "https://machengine.org/zig/index.json"

--- Splits a version into its numbers and its pre-release identifiers. The build
--- metadata after `+` (the commit of a development build) is left out, as it is
--- left out of the order in semantic versioning.
--- @param version string
--- @return table numbers
--- @return table identifiers
local function split_version(version)
    local without_build = version:match("^[^+]*")
    local core, pre = without_build:match("^([^%-]*)%-(.*)$")
    if core == nil then
        core, pre = without_build, ""
    end
    local numbers = {}
    for part in core:gmatch("[^.]+") do
        table.insert(numbers, tonumber(part) or 0)
    end
    local identifiers = {}
    for part in pre:gmatch("[^.]+") do
        table.insert(identifiers, part)
    end
    return numbers, identifiers
end

--- Returns -1, 0 or 1 as a sorts before, with or after b, for two numbers or two strings.
local function compare_values(a, b)
    if a < b then
        return -1
    elseif a > b then
        return 1
    end
    return 0
end

--- Orders two pre-release identifiers: numbers by value, text by its bytes, and a number before text.
local function compare_identifiers(a, b)
    local a_number = a:match("^%d+$") ~= nil
    local b_number = b:match("^%d+$") ~= nil
    if a_number and b_number then
        return compare_values(tonumber(a), tonumber(b))
    elseif a_number then
        return -1
    elseif b_number then
        return 1
    end
    return compare_values(a, b)
end

--- Returns -1, 0 or 1 as version a sorts before, with or after version b.
--- Versions compare by their numbers, and a pre-release sorts before the release
--- of the same numbers, so 0.14.0-dev.2577 comes before 0.14.0. Versions that tie
--- compare by their text, so the same list comes out on every run.
--- @param a string
--- @param b string
--- @return number
function util.compare_versions(a, b)
    local a_numbers, a_pre = split_version(a)
    local b_numbers, b_pre = split_version(b)
    for i = 1, math.max(#a_numbers, #b_numbers) do
        local order = compare_values(a_numbers[i] or 0, b_numbers[i] or 0)
        if order ~= 0 then
            return order
        end
    end
    if #a_pre == 0 and #b_pre > 0 then
        return 1
    elseif #a_pre > 0 and #b_pre == 0 then
        return -1
    end
    for i = 1, math.max(#a_pre, #b_pre) do
        -- The shorter list of identifiers sorts first when all of its own match.
        if a_pre[i] == nil then
            return -1
        elseif b_pre[i] == nil then
            return 1
        end
        local order = compare_identifiers(a_pre[i], b_pre[i])
        if order ~= 0 then
            return order
        end
    end
    return compare_values(a, b)
end

--- Reports whether a version is a pre-release, such as a development build.
--- @param version string
--- @return boolean
function util.is_prerelease(version)
    local _, identifiers = split_version(version)
    return #identifiers > 0
end

--- Downloads an index and decodes it. The error names the URL and the reason,
--- without the position in this file that error would add (level 0), since it
--- is shown to the user as it stands.
--- @param url string
--- @return table
function util.fetch_index(url)
    local resp, err = http.get({
        url = url,
    })
    if err ~= nil then
        error("cannot download " .. url .. ": " .. tostring(err), 0)
    end
    if resp.status_code ~= 200 then
        error("cannot download " .. url .. ": status_code => " .. tostring(resp.status_code), 0)
    end
    local index = json.decode(resp.body)
    if type(index) ~= "table" then
        error("cannot read " .. url .. ": the index is not a JSON object", 0)
    end
    return index
end

--- Returns the platform record of a build for the first architecture the
--- platform has, or nil.
local function platform_of(build, archs, os_type)
    for _, arch in ipairs(archs) do
        local platform = build[arch .. "-" .. os_type]
        if type(platform) == "table" then
            return platform
        end
    end
    return nil
end

--- Lists the builds of one index that are available for this platform.
--- A build is named by its key, unless it has a version of its own and the
--- key is that version's name (`0.17.1`): `master` is the nightly, and any
--- other key that differs from the version is an alias (`2024.11.0-mach`).
--- The keys are read in sorted order, so the result does not depend on how
--- the table is traversed. A build whose `archive` address differs from its
--- `tarball` address keeps the latter as fallback_url: ziglang.org has pruned
--- some of Mach's development builds, which still download from `tarball`.
--- @param index table The decoded index
--- @param archs table Architecture names as the index spells them
--- @param os_type string Operating system as the index spells it
--- @param archive string Key of the archive URL in a platform record
--- @param skip table Keys to leave out
--- @return table list of { version, url, fallback_url, sha256, aliases }
function util.platform_builds(index, archs, os_type, archive, skip)
    local keys = {}
    for key in pairs(index) do
        if not skip[key] then
            table.insert(keys, key)
        end
    end
    table.sort(keys)

    local builds = {}
    for _, key in ipairs(keys) do
        local build = index[key]
        local platform = type(build) == "table" and platform_of(build, archs, os_type) or nil
        if platform ~= nil then
            local url = platform[archive] or platform.tarball
            if type(url) == "string" and url ~= "" then
                local version = key
                if type(build.version) == "string" then
                    version = build.version
                end
                local aliases = {}
                if key == "master" then
                    aliases = { "nightly" }
                elseif key ~= version then
                    aliases = { key }
                end
                local fallback = nil
                if archive ~= "tarball" and type(platform.tarball) == "string" and platform.tarball ~= url then
                    fallback = platform.tarball
                end
                table.insert(builds, {
                    version = version,
                    url = url,
                    fallback_url = fallback,
                    sha256 = type(platform.shasum) == "string" and platform.shasum or nil,
                    aliases = aliases,
                })
            end
        end
    end
    return builds
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

--- Adds builds to the releases, which are keyed by version. The first build
--- of a version gives its URLs and SHA-256, and every build adds its names.
local function add_builds(releases, builds)
    for _, build in ipairs(builds) do
        local release = releases[build.version]
        if release == nil then
            release = {
                version = build.version,
                url = build.url,
                fallback_url = build.fallback_url,
                sha256 = build.sha256,
                aliases = {},
            }
            releases[build.version] = release
        end
        for _, alias in ipairs(build.aliases) do
            if not contains(release.aliases, alias) then
                table.insert(release.aliases, alias)
            end
        end
    end
end

--- Returns every build of this platform. Official releases come first, newest
--- first, then the development builds, newest first. vfox takes the first entry
--- as the latest for `zig@latest`, so the order is what makes that the newest
--- release and not the newest nightly. Each build carries the names it has:
--- `latest` on the newest release, `nightly`, and the Mach names.
--- Mach's index is optional. When it cannot be read, the official releases
--- are listed alone, with a warning, so one unreachable index does not stop
--- every install.
--- @return table list of { version, url, sha256, aliases }
function util:releases()
    local archs = self:getArchArr()
    local os_type = self:getOsType()
    local releases = {}

    add_builds(releases, util.platform_builds(util.fetch_index(util.BaseUrl), archs, os_type, "tarball", {}))

    -- Mach's master is a nightly of its own fork and shares a version with the
    -- builds Mach names, so only those are listed.
    local ok, mach = pcall(util.fetch_index, util.MachUrl)
    if ok then
        add_builds(releases, util.platform_builds(mach, archs, os_type, "zigTarball", { master = true }))
    else
        print("WARNING: " .. tostring(mach) .. "; listing the official releases only")
    end

    local list = {}
    for _, release in pairs(releases) do
        table.insert(list, release)
    end
    table.sort(list, function(a, b)
        local a_pre = util.is_prerelease(a.version)
        local b_pre = util.is_prerelease(b.version)
        if a_pre ~= b_pre then
            return b_pre
        end
        return util.compare_versions(a.version, b.version) > 0
    end)
    for _, release in ipairs(list) do
        if not util.is_prerelease(release.version) then
            table.insert(release.aliases, "latest")
            break
        end
    end
    return list
end

--- Reports whether a download address answers. A HEAD request asks without
--- downloading the archive.
--- @param url string
--- @return boolean
function util.reachable(url)
    local resp, err = http.head({
        url = url,
    })
    return err == nil and resp ~= nil and resp.status_code == 200
end

--- Returns the address to download a release from: its first address, unless
--- that one does not answer and the index gives another for the same build.
--- @param release table As returned by util:releases()
--- @return string
function util.download_url(release)
    if release.fallback_url ~= nil and not util.reachable(release.url) then
        return release.fallback_url
    end
    return release.url
end

--- Finds the release a name refers to: first a version, then one of the names
--- a release has.
--- @param releases table As returned by util:releases()
--- @param name string
--- @return table|nil
function util.find_release(releases, name)
    for _, release in ipairs(releases) do
        if release.version == name then
            return release
        end
    end
    for _, release in ipairs(releases) do
        if contains(release.aliases, name) then
            return release
        end
    end
    return nil
end

function util:getOsType()
    if RUNTIME.osType == "darwin" then
        return "macos"
    end
    return RUNTIME.osType
end

-- The names the index gives each architecture that vfox reports under its Go
-- name, in the order to try them. Go names some architectures differently from
-- the index (loong64 is loongarch64, ppc is powerpc), and some releases list an
-- architecture under another name, such as armv7a for arm up to 0.14.1.
local arch_names = {
    amd64 = { "x86_64" },
    arm64 = { "aarch64" },
    ["386"] = { "x86", "i386" },
    arm = { "arm", "armv7a" },
    ppc = { "powerpc" },
    ppc64le = { "powerpc64le" },
    loong64 = { "loongarch64" },
}

function util:getArchArr()
    return arch_names[RUNTIME.archType] or { RUNTIME.archType }
end

return util
