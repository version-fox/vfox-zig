local http = require("http")
local json = require("json")
local util = {}
util.BaseUrl = "https://ziglang.org/download/index.json"
util.MachUrl = "https://machengine.org/zig/index.json"

function util:compare_versions(v1o, v2o)
    local v1 = v1o.version
    local v2 = v2o.version
    local v1_parts = {}
    for part in string.gmatch(v1, "[^.+-]+") do
        table.insert(v1_parts, tonumber(part))
    end

    local v2_parts = {}
    for part in string.gmatch(v2, "[^.+-]+") do
        table.insert(v2_parts, tonumber(part))
    end

    for i = 1, math.max(#v1_parts, #v2_parts) do
        local v1_part = v1_parts[i] or 0
        local v2_part = v2_parts[i] or 0
        if v1_part > v2_part then
            return true
        elseif v1_part < v2_part then
            return false
        end
    end

    return false
end


function util:getResults(url, archs, os, tar)
    local resp, err = http.get({
        url = url,
    })
    if err ~= nil or resp.status_code ~= 200 then
        error("get version failed" .. err)
    end
    local body = json.decode(resp.body)
    local result = {}
    for k, v in pairs(body) do
        local version = k
        local note = ""
        if v.version ~= nil then
            version = v.version
            if k == "master" then
                note = "nightly"
            else
                note = k
            end
        end
        for _, arch in ipairs(archs) do
            local key = arch .. "-" .. os
            if v[key] ~= nil then
                if result[version] ~= nil then
                    result[version].note = result[version].note .. "|" .. note
                else
                    result[version] = {
                        version = version,
                        url = v[key][tar],
                        sha256 = v[key].shasum,
                        note = note,
                    }
                end
            end
        end
    end
    return result
end

function util:getOsType()
    if RUNTIME.osType == "darwin" then
        return "macos"
    end
    return RUNTIME.osType
end

function util:getArchArr()
    if RUNTIME.archType == "amd64" then
        return {
            "x86_64",
        }
    elseif RUNTIME.archType == "arm64" then
        return {
            "aarch64",
        }
    elseif RUNTIME.archType == "386" then
        return {
            "x86",
            "i386",
        }
    else
        return {
            RUNTIME.archType,
        }
    end
end

return util