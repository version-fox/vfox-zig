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
test.load({
    os = "linux",
    arch = "amd64",
})
local util = require("util")

-- Version order follows semantic versioning: numbers compare by value, and a
-- pre-release sorts before its release. Development builds carry a commit after
-- `+`, which does not count.
local orders = {
    { "0.17.1", "0.17.0", 1 },
    { "0.10.1", "0.9.1", 1 },
    { "0.17.0", "0.17.0", 0 },
    { "0.14.0", "0.14.0-dev.2577+271452d22", 1 },
    { "0.14.0-dev.2577+271452d22", "0.14.0", -1 },
    { "0.14.0-dev.2577", "0.14.0-dev.1911", 1 },
    { "0.18.0-dev.935+ead8f5a7a", "0.18.0-dev.1260+833623422", -1 },
    { "0.17.0-dev.2228+955228b68", "0.17.0", -1 },
    -- Identifiers: numbers by value, text after numbers, a longer list after its prefix.
    { "1.0.0-alpha", "1.0.0-alpha.1", -1 },
    { "1.0.0-alpha.1", "1.0.0-alpha.beta", -1 },
    { "1.0.0-alpha.beta", "1.0.0-beta", -1 },
    { "1.0.0-2", "1.0.0-10", -1 },
    -- Versions that tie in precedence keep a stable order by their text.
    { "2.0.0+build1", "2.0.0+build2", -1 },
    { "2.0.0+build2", "2.0.0+build1", 1 },
}
for _, case in ipairs(orders) do
    local got = util.compare_versions(case[1], case[2])
    assert(got == case[3], ("compare_versions(%s, %s): expected %d, got %d"):format(case[1], case[2], case[3], got))
    local reversed = util.compare_versions(case[2], case[1])
    assert(
        reversed == -case[3] or (case[3] == 0 and reversed == 0),
        ("compare_versions is not antisymmetric for %s and %s"):format(case[1], case[2])
    )
end

-- Sorting with the comparator gives the same, newest-first list every time.
local shuffled = { "0.14.0", "0.14.0-dev.2577+271452d22", "0.17.1", "0.9.1", "0.17.0-dev.2228+955228b68", "0.17.0" }
table.sort(shuffled, function(a, b)
    return util.compare_versions(a, b) > 0
end)
local expected = { "0.17.1", "0.17.0", "0.17.0-dev.2228+955228b68", "0.14.0", "0.14.0-dev.2577+271452d22", "0.9.1" }
for i, version in ipairs(expected) do
    assert(shuffled[i] == version, ("position %d: expected %s, got %s"):format(i, version, shuffled[i]))
end

local prereleases = {
    ["0.14.0-dev.2577+271452d22"] = true,
    ["0.18.0-dev.1260+833623422"] = true,
    ["2024.11.0-mach"] = true,
    ["0.14.0"] = false,
    ["0.17.1"] = false,
    ["0.14.0+abc123"] = false,
}
for version, want in pairs(prereleases) do
    assert(util.is_prerelease(version) == want, ("is_prerelease(%s) should be %s"):format(version, tostring(want)))
end

-- platform_builds: keys are sorted, a version-named key is no alias, master is
-- the nightly, other keys are aliases, and platforms other than ours are left out.
local index = {
    master = {
        version = "0.18.0-dev.1+aaaaaaaa",
        ["x86_64-linux"] = { tarball = "https://ziglang.org/builds/master.tar.xz", shasum = "aa" },
    },
    ["0.17.1"] = {
        version = "0.17.1",
        ["x86_64-linux"] = { tarball = "https://ziglang.org/download/0.17.1/a.tar.xz", shasum = "bb" },
        ["x86_64-windows"] = { tarball = "https://ziglang.org/download/0.17.1/a.zip", shasum = "cc" },
    },
    ["0.13.0"] = {
        ["x86_64-linux"] = { tarball = "https://ziglang.org/download/0.13.0/b.tar.xz", shasum = "dd" },
    },
    ["mach-latest"] = {
        version = "0.18.0-dev.2+bbbbbbbb",
        ["x86_64-linux"] = {
            tarball = "https://pkg.example/m.tar.xz",
            zigTarball = "https://ziglang.org/builds/m.tar.xz",
            shasum = "ee",
        },
    },
    ["broken"] = "not a build",
}
-- Keys are read sorted: 0.13.0, 0.17.1, broken (not a build, left out), mach-latest, master.
local builds = util.platform_builds(index, { "x86_64" }, "linux", "tarball", {})
assert(#builds == 4, ("expected 4 linux builds, got %d"):format(#builds))
assert(builds[1].version == "0.13.0" and #builds[1].aliases == 0, "0.13.0 has no alias")
assert(builds[2].version == "0.17.1" and #builds[2].aliases == 0, "0.17.1 has no alias: its key is its version")
assert(
    builds[3].version == "0.18.0-dev.2+bbbbbbbb" and builds[3].aliases[1] == "mach-latest",
    "a Mach name is an alias"
)
assert(builds[4].version == "0.18.0-dev.1+aaaaaaaa" and builds[4].aliases[1] == "nightly", "master is the nightly")
assert(
    builds[4].url == "https://ziglang.org/builds/master.tar.xz" and builds[4].sha256 == "aa",
    "url and checksum of master"
)

-- Mach's archive is zigTarball; a build without one falls back to tarball, and
-- master is left out when asked.
local mach = util.platform_builds(index, { "x86_64" }, "linux", "zigTarball", { master = true })
assert(#mach == 3, ("expected 3 builds without master, got %d"):format(#mach))
assert(mach[2].url == "https://ziglang.org/download/0.17.1/a.tar.xz", "no zigTarball: the tarball is used")
assert(mach[3].version == "0.18.0-dev.2+bbbbbbbb", "mach build version")
assert(mach[3].url == "https://ziglang.org/builds/m.tar.xz", "mach builds download from zigTarball")
assert(mach[3].aliases[1] == "mach-latest", "mach names are aliases")

-- The other address of a build is its fallback: the tarball when the archive is
-- zigTarball, and nothing where the archive is the tarball itself.
assert(mach[3].fallback_url == "https://pkg.example/m.tar.xz", "the tarball is the fallback of a Mach build")
assert(mach[2].fallback_url == nil, "no fallback where the archive is the tarball itself")
assert(builds[3].fallback_url == nil, "no fallback for the tarball archive")

-- A platform with a different arch or OS gives nothing.
assert(#util.platform_builds(index, { "aarch64" }, "linux", "tarball", {}) == 0, "no aarch64 builds in this index")
assert(#util.platform_builds(index, { "x86_64" }, "windows", "tarball", {}) == 1, "one windows build")

-- Go's architecture names map to the ones the index spells, first choice first.
local archs = {
    amd64 = { "x86_64" },
    arm64 = { "aarch64" },
    ["386"] = { "x86", "i386" },
    arm = { "arm", "armv7a" },
    ppc = { "powerpc" },
    ppc64le = { "powerpc64le" },
    loong64 = { "loongarch64" },
    riscv64 = { "riscv64" },
}
for go_arch, zig_names in pairs(archs) do
    RUNTIME.archType = go_arch
    local names = util:getArchArr()
    assert(#names == #zig_names, ("arch %s: expected %d names, got %d"):format(go_arch, #zig_names, #names))
    for i, zig_arch in ipairs(zig_names) do
        assert(names[i] == zig_arch, ("arch %s should be %s, got %s"):format(go_arch, zig_arch, tostring(names[i])))
    end
end
RUNTIME.archType = "amd64"
RUNTIME.osType = "darwin"
assert(util:getOsType() == "macos", "darwin is spelled macos in the index")
RUNTIME.osType = "linux"

print("util tests passed")
