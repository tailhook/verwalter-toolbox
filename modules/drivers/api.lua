local package = (...):match("(.-)[^/]+$")
local super = package:match("(.-)[^/]+/$")
local version_util = require(super..'version_util')
local T = require(super..'trafaret')
local log = require(super..'log')
local func = require(super..'func')
local ACTIONS = {}

local ACTION = T.Or {
    T.Dict {
        button=T.Dict {
            role=T.String {},
            action=T.Atom { "create_group" },
            group_name=T.String {},
            version=T.String {},
        },
    },
    T.Dict {
        button=T.Dict {
            role=T.String {},
            action=T.Atom { "add_daemon" },
            group_name=T.String {},
            daemon_name=T.String {},
            servers=T.List { T.String {} },
            number_per_server=T.Number {},
            variables=T.Dict { allow_extra=true },
        },
    },
}

local STATE = T.Dict {
    [T.Key { "groups", default={} }]=T.Map { T.String {}, T.Dict {
        version=T.String {},
    }},
}

local function check_actions(role, actions)
    local invalid_actions = {}
    local valid_actions = {}
    for ts, action in pairs(actions) do
        local status, val, err = T.validate(ACTION, action)
        if status then
            log.role_debug(role.name, "action", val.button.action, "is valid")
            table.insert(valid_actions, val)
        else
            for _, e in ipairs(err) do
                log.role_error(role.name, 'action', action, 'is invalid:', e)
            end
        end
    end
    return valid_actions, invalid_actions
end

local function merge_states(role, parents)
    local groups = {}
    for _, parent in pairs(parents) do
        local status, val, err = T.validate(STATE, parent.state)
        if status then
            for group_name, group in pairs(val.groups) do
                if groups[group_name] ~= nil then
                    -- TODO(tailhook) merge somehow
                else
                    groups[group_name] = group
                end
            end
        else
            for _, e in ipairs(err) do
                log.role_error(role.name,
                    'parent state',
                    parent.hash or 'unknown-hash',
                    'from',
                    parent.origin or 'unknown-host',
                    'is invalid:', e)
            end
        end
    end
    local ngroups = func.count_keys(groups)
    if ngroups == 0 then
        log.role_debug(role.name, "No groups configured")
    else
        log.role_debug(role.name, ngroups, "groups found")
    end
    local tmp_state = {
        groups=groups,
    }
    local status, state, err = T.validate(STATE, tmp_state)
    if not status then
        for _, e in ipairs(err) do
            log.role_error(role.name, 'merged state is invalid:', e)
        end
    end
    return state
end

function ACTIONS.create_group(role, action, timestamp)
    local button = action.button
    if role.state.groups[button.group_name] then
        log.role_error(role.name, 'group', button.group_name,
            'already exists')
    else
        log.role_change(role.name, 'new group', button.group_name)
        role.state.groups[button.group_name] = {
            version=button.version,
        }
    end
end

local function execute_actions(role, actions)
    for timestamp, a in pairs(actions) do
        local aname = a.button.action
        log.role_debug(role.name, 'action', aname)
        local func = ACTIONS[aname]
        if func ~= nil then
            -- TODO(tailhook) maybe use xpcall ?
            func(role, a, timestamp)
        else
            log.role_error(role.name, 'action', aname, 'is unknown. Skipped.')
        end
    end

    local status, state, err = T.validate(STATE, role.state)
    if not status then
        for _, e in ipairs(err) do
            log.role_error(role.name,
                'state is invalid after executing actions:', e)
        end
    end
end

local function prepare(params)
    local role = params[1]
    local global_state = params.global_state

    local sorted, vers, rparams = version_util.split_versions(params.runtime)
    -- TODO(tailhook) validate versions
    role.params = rparams
    role.versions = vers
    role.descending_versions = sorted

    local actions, invalid_actions = check_actions(role, params.actions)
    role.actions = actions
    role.invalid_actions = invalid_actions

    local state = merge_states(role, params.parents)
    role.state = state

    execute_actions(role, role.actions)
end

return {
    prepare=prepare,
}
