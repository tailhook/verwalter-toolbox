local package = (...):match("(.-)[^/]+$")
local func = require(package..'func')
local log = require(package..'log')

local _Role = {}

function _Role:output()
    local images = {}
    for _, ver in pairs(self.alive_versions or {}) do
        local version_info = self.versions[ver] or {}
        if version_info.containers then  -- keep all containers of a version
            for _, val in pairs(version_info.containers) do
                images[val] = true
            end
        else
            local daemons = version_info.daemons or {}
            for _, daemon in pairs(daemons) do
                images[daemon.image] = true
            end
            local commands = version_info.commands or {}
            for _, cmd in pairs(commands) do
                images[cmd.image] = true
            end
        end
    end
    local versions = self.alive_versions or self.descending_versions
    local version_info = {}
    for _, ver in pairs(versions) do
        version_info[ver] = self.versions[ver] or {daemons={}}
    end
    return {
        state=func.dict_or_nil(self.state),
        role={
            frontend={kind='api'},
            versions=versions,
            version_info=version_info,
            images=func.keys(images),
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
    params.log = log.Logger(params.name)
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
            hooks=params.hooks,
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
