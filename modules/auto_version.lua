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
    -- a split-brain.
    if button ~= nil and
        (parent == nil or button.timestamp > parent.timestamp)
    then
        print("Version switched by user to", button.version)
        -- We mark timestamp as `now` instead of button timestamp, because
        -- if split-brain is joined shortly after we pressed the button,
        -- and on the other side of the split-brain scheduler has later
        -- timestamp we should ignore it.
        --
        -- There is still a race condition in split-brain case.
        -- More comprehensive scheduler might give button an "expire"
        -- timestamp. I.e. some time in the future that the automatic
        -- scheduler is not allowed to update until.
        return sorted_versions, {
            version=button.version,
            timestamp=props.now,
        }
    end

    local auto_version_no = sorted_versions[#sorted_versions]
    local auto_version = {
        version=auto_version_no,
        timestamp=(props.runtime[auto_version_no].timestamp or 0)*1000
    }

    if parent ~= nil and auto_version.timestamp <= parent.timestamp then
        print("Chosen parent version", parent.version,
              "with timestamp", parent.timestamp)
        return sorted_versions, parent
    end

    print("Auto version is", auto_version.version)
    return sorted_versions, auto_version
end

return {
    select=select,
}
