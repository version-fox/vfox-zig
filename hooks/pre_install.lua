--- Returns some pre-installed information, such as version number, download address, local files, etc.
--- If checksum is provided, vfox will automatically check it for you.
--- @param ctx table
--- @field ctx.version string User-input version
--- @return table Version information
function PLUGIN:PreInstall(ctx)
    local version = ctx.version
    local releases = self:Available({})
    for _, release in ipairs(releases) do
        if release.version == version then
            return release
        else
            for note in string.gmatch(release.note, "[^|]+") do
                if note == version then
                    return release
                end
            end
        end
    end
    return {}
end