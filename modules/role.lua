local package = (...):match("(.-)[^/]+$")
local func = require(package..'func')

local _Role = {}

function _Role:output()
    return {
        state=self.state,
        role={
            frontend={kind='api'},
            versions=self.descending_versions,
        },
        nodes={},
        metrics={},
    }
end

local function tostring(self)
    return 'Role "'..self.name..'" {}'
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
                result[role_name] = {{state=role_state}}
            else
                table.insert(tbl, {state=role_state})
            end
        end
    end

    return result
end

-- this is mostly for tests
local function from_fields(params)
    setmetatable(params, {__index=_Role, __tostring=tostring})
    return params
end

local function from_state(params)
    local state = params[1]
    local driver_func = params.driver

    local actions = split_actions(state)
    local states = split_states(state)
    return func.map_pairs(function(role_name, runtime)

        local role = from_fields({
            name=role_name,
        })
        local driver = driver_func(role, runtime)
        driver.prepare { role,
            runtime=runtime,
            global_state=state,
            actions=actions[role_name] or {},
            parents=states[role_name] or {},
        }

        return role
    end, state.runtime)
end

local function merge_output(dict)
    local result = {
        state={},
        roles={},
        nodes={},
    }
    for role_name, role in pairs(dict) do
        local output = role:output()
        result.state[role_name] = output.state
        result.roles[role_name] = output.role
        for node_name, node_role in pairs(role.nodes or {}) do
            local mnode = result.nodes[node_name]
            if mnode == nil then
                mnode = {
                    roles={},
                }
                result.nodes[node_name] = mnode
            end
            mnode.roles[role_name] = node_role
        end
    end
    return result
end

return {
    from_state=from_state,
    from_fields=from_fields,  -- for tests
    merge_output=merge_output,
}
