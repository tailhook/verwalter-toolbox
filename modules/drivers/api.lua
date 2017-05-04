local package = (...):match("(.-)[^/]+$")
local super = package:match("(.-)[^/]+/$")
local version_util = require(super..'version_util')

local function prepare(params)
    local role = params[1]
    local runtime = params.runtime
    local global_state = params.global_state
    local actions = params.actions
    local parents = params.states
    local sorted, versions, params = version_util.split_versions(runtime)

    -- TODO(tailhook) validate versions, actions and parents
    role.params = params
    role.versions = versions
    role.descending_versions = sorted
    role.actions = actions
    role.parents = parents
end

return {
    prepare=prepare,
}
