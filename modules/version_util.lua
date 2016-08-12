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

return {
    version_numbers=version_numbers
}
