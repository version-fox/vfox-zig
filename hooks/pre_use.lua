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

--- @class PreUseContext
--- @field version string The name typed
--- @field installedSdks table Installed versions, keyed by name

--- When the user invokes `use`, this maps the name typed to the installed version
--- it refers to. An installed name is left to vfox, and so is a bare or dotted
--- number, which vfox matches against the installed versions itself. A name such
--- as `latest`, `nightly` or a Mach name is looked up in the index, so it needs
--- the network, and selects the version it names when that version is installed.
--- @param ctx PreUseContext
function PLUGIN:PreUse(ctx)
    local input = ctx.version
    local installed = ctx.installedSdks or {}
    if input == nil or installed[input] ~= nil or input:match("^%d+[%d.]*$") then
        -- Return nil rather than a string: vfox after 1.0.12 rejects a bare string.
        return nil
    end
    local ok, releases = pcall(util.releases, util)
    if not ok then
        util.warn("WARNING: cannot resolve " .. input .. " from the index: " .. tostring(releases))
        return nil
    end
    local release = util.find_release(releases, input)
    if release ~= nil and installed[release.version] ~= nil then
        return {
            version = release.version,
        }
    end
    return nil
end
