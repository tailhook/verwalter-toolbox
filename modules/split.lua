local package = (...):match("(.-)[^/]+$")
local func = require(package..'func')
local version_util = require(package..'version_util')

local function get_actions(state, role_name)
    return func.filter_pairs(
        function (ts, act)
            if act.button.role == role_name then
                return ts, act
            end
        end,
        state.actions)
end

local function get_states(state, role_name)
    local curstates = {}
    for _, par in pairs(state.parents) do
        if par.state ~= nil and par.state[role_name] ~= nil then
            curstates[#curstates+1] = par.state[role_name]
        end
    end
    return curstates
end

local function get_metrics(state, role_name)
    local pattern = "^" .. role_name:gsub("-", "%%-") .. "%.(.+)$"
    local metrics = {}

    if state.metrics then
        metrics = func.filter_pairs(
            function (node_id, node_metrics)
                local peer = state.peers[node_id]
                if peer == nil then
                    return nil, nil
                end

                return peer.hostname, func.filter_pairs(
                    function (k, v)
                        local localk = k:match(pattern)
                        if localk ~= nil then
                            return localk, v
                        end
                    end,
                    node_metrics)
            end,
            state.metrics)
    end
    return metrics
end

local function state_by_role(state, config)
    return func.map_to_dict(function(role_name, role_cfg)
        local runtime = state.runtime[role_cfg.runtime] or {}
        local sorted, versions, params = version_util.split_versions(runtime)
        return role_name, {
            role=role_name,

            -- legacy runtime
            runtime=runtime,
            -- new runtime
            parameters=params,
            versions=versions,
            descending_versions=sorted,

            -- split state
            actions=get_actions(state, role_name),
            parents=get_states(state, role_name),
            metrics=get_metrics(state, role_name),

            -- config
            daemons=role_cfg.daemons,

            -- global things
            peers=state.peers,
            peer_set=state.peer_set,
            now=state.now,
        }
    end, config)
end

return {
    actions=get_actions,
    states=get_states,
    metrics=get_metrics,
    state_by_role=state_by_role,
}
