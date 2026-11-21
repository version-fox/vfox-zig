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

--- @class PreInstallContext
--- @field version string User-input version, or a name such as latest

--- Returns the download of the release that a version or a name refers to.
--- The version is the name of the install, and the SHA-256 is checked by vfox.
--- @param ctx PreInstallContext
--- @return table Version information
function PLUGIN:PreInstall(ctx)
    local version = ctx.version
    if version == nil or version == "" then
        error("No version given. Pick one from `vfox search zig`, such as zig@latest")
    end
    local release = util.find_release(util:releases(), version)
    if release == nil then
        error(
            ("zig %s is not listed for %s/%s; `vfox search zig` lists the versions"):format(
                version,
                RUNTIME.osType,
                RUNTIME.archType
            )
        )
    end
    return {
        version = release.version,
        url = util.download_url(release),
        sha256 = release.sha256,
        note = table.concat(release.aliases, ", "),
    }
end
