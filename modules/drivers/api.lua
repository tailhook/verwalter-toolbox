local package = (...):match("(.-)[^/]+$")
local super = package:match("(.-)[^/]+/$")
local version_util = require(super..'version_util')
local T = require(super..'trafaret')
local log = require(super..'log')

local ACTION = T.Or {
    T.Dict {
        button=T.Dict {
            role=T.String {},
            action=T.Atom { "create_group" },
            group_name=T.String {},
            group_version=T.String {},
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

local function check_actions(role, actions)
    local invalid_actions = {}
    local valid_actions = {}
    for ts, action in pairs(actions) do
        local status, val, err = T.validate(ACTION, action)
        if status then
            log.role_debug(role.name, "action", val.button.action, "is valid")
            table.insert(actions, val)
        else
            for _, e in ipairs(err) do
                log.role_error(role.name, 'action', action, 'is invalid:', e)
            end
        end
    end
    return valid_actions, invalid_actions
end

local function prepare(params)
    local role = params[1]
    local global_state = params.global_state
    local parents = params.states

    local actions, invalid_actions = check_actions(role, params.actions)
    local sorted, vers, params = version_util.split_versions(params.runtime)

    -- TODO(tailhook) validate versions and parents
    role.params = params
    role.versions = vers
    role.descending_versions = sorted

    role.actions = actions
    role.invalid_actions = invalid_actions

    role.parents = parents
end

return {
    prepare=prepare,
}
