local package = (...):match("(.-)[^/]+$")
local version = require(package.."version")

-- The runtime dictionary is a "runtime" folder from verwalter
-- which basically represents a directory. So it contains both: version
-- number directories and some plain files with project scoped metadata.
--
-- This function filters out only version numbers
local function version_numbers(runtime)
    local list = {}
    local set = {}
    for ver, _ in pairs(runtime) do
        if ver:find("^v%d") then
            list[#list+1] = ver
            set[ver] = true
        end
    end
    table.sort(list, version.compare)
    return list, set
end

local function latest_version_button(actions, valid_versions)
    local latest = nil
    for timestamp, act in pairs(actions) do
        if act.button and act.button.version then
            local ver = act.button.version
            if valid_versions[ver] then
                if latest == nil or latest.timestamp < timestamp then
                    latest = {
                        version=ver,
                        timestamp=timestamp
                    }
                end
            else
                print("Version", ver, "activated by user is invalid")
            end
        end
    end
    return latest
end

return {
    version_numbers=version_numbers,
    latest_version_button=latest_version_button,
}
