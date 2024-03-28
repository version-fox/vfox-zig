local util = require("util")

--- Return all available versions provided by this plugin
--- @param ctx table Empty table used as context, for future extension
--- @return table Descriptions of available versions and accompanying tool descriptions
function PLUGIN:Available(ctx)
    local archs = util:getArchArr()
    local os = util:getOsType()
    local base = util:getResults(util.BaseUrl, archs, os, "tarball")
    local mach = util:getResults(util.MachUrl, archs, os, "zigTarball")

    --merge the two together
    for k, v in pairs(mach) do
        if v.note == "nightly" then
            goto continue
        end
        if base[k] == nil then
            base[k] = v
        elseif base[k].note ~= "" then
            base[k].note = base[k].note .. "|" .. v.note
        end
        ::continue::
    end

    -- Need an list to sort it
    local result = {}
    for _, v in pairs(base) do
        table.insert(result, v)
    end
    table.sort(result, function(a,b) return util:compare_versions(a,b) end)

    -- Get the first non-noted version to dictate latest
    for _, v in ipairs(result) do
        if v.note == "" then
            v.note = "latest"
            break
        end
    end
    return result
end