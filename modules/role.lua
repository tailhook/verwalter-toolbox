local package = (...):match("(.-)[^/]+$")
local func = require(package..'func')
local version_util = require(package..'version_util')

local _Role = {}

function _Role:independent_scheduling()
    local _ = self
end

function _Role:output()
    local _ = self
    return {
        state={},
        role={},
        nodes={},
        metrics={},
    }
end

local function split_actions(state)
    local result = {}

    for timestamp, action in pairs(state.actions) do
        local role = action.button and action.button.role
        if role then
            local tbl = result[role]
            if tbl == nil then
                result[role] = {[timestamp] = action}
            else
                tbl[timestamp] = action
            end
        end
    end

    return result
end

local function split_states(state)
    local result = {}

    for _, par in pairs(state.parents) do
        for role_name, role_state in pairs(par.state) do
            local tbl = result[role_name]
            if tbl == nil then
                result[role_name] = {role_state}
            else
                table.insert(tbl, role_state)
            end
        end
    end

    return result
end

local function from_state(state)
    local actions = split_actions(state)
    local states = split_states(state)
    return func.map_pairs(function(role_name, runtime)
        local sorted, versions, params = version_util.split_versions(runtime)
        local role = {
            name=role_name,

            parameters=params,
            versions=versions,
            descending_versions=sorted,

            actions=actions[role_name] or {},
            parents=states[role_name] or {},
            -- TODO(tailhook)
            -- metrics=get_metrics(state, role_name),
        }
        setmetatable(role, _Role)
        return role
    end, state.runtime)
end

return {
    from_state=from_state,
}
