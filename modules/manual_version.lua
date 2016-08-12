local package = (...):match("(.-)[^/]+$")
local version_util = require(package.."version_util")
local version_numbers = version_util.version_numbers
local latest_version_button = version_util.latest_version_button
local latest_parent_version = version_util.latest_parent_version

-- The props here is the result of applying a split module to a schedule
-- (more will be documented later)
local function select(props)

    local sorted_versions, version_set = version_numbers(props.runtime)

    local button = latest_version_button(props.actions, version_set)
    local parent = latest_parent_version(props.parents, version_set)

    -- We check if someone pressed button later on the other side of
    -- a split-brain
    if button ~= nil and (parent == nil or button.timestamp > parent.timestamp)
    then
        print("Version switched by user to", button.version)
        return sorted_versions, button
    end

    if parent ~= nil then
        print("Chosen parent version", parent.version,
              "with timestamp", parent.timestamp)
        return sorted_versions, parent
    end

    print("Default version is", sorted_versions[#sorted_versions])
    -- Return zero timestamp, for the case someone have already chosen version
    -- on the other side of the split brain
    return sorted_versions, {
        version=sorted_versions[#sorted_versions],
        timestamp=0,
    }
end

return {
    select=select,
}
