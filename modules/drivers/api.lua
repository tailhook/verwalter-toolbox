local package = (...):match("(.-)[^/]+$")
local super = package:match("(.-)[^/]+/$")
local version_util = require(super..'version_util')
local version = require(super..'version')
local T = require(super..'trafaret')
local func = require(super..'func')
local update = require(super..'update')
local repr = require(super..'repr')
local ACTIONS = {}
local LAST_DEPLOYED_LIFETIME = 86400
local LAST_UPLOADED_LIFETIME = 86400

local ACTION = T.Dict {
    button=T.Choice {
        "action",
        create_group=T.Dict {
            action=T.Atom { "create_group" },
            role=T.String {},
            group_name=T.String {},
            version=T.String {},
        },
        add_daemon=T.Dict {
            action=T.Atom { "add_daemon" },
            role=T.String {},
            group=T.String {},
            new_name=T.String {},
            service=T.String {},
            servers=T.List { T.String {} },
            number_per_server=T.Number {},
            variables=T.Map { T.String {},
                              T.Or { T.String {}, T.Number {} } },
        },
        enable_auto_update=T.Dict {
            action=T.Atom { "enable_auto_update" },
            role=T.String {},
            group=T.String {},
        },
        disable_auto_update=T.Dict {
            action=T.Atom { "disable_auto_update" },
            role=T.String {},
            group=T.String {},
        },
        force_version=T.Dict {
            action=T.Atom { "force_version" },
            role=T.String {},
            group=T.String {},
            to_version=T.String {},
        },
        start_update=T.Dict {
            action=T.Atom { "start_update" },
            role=T.String {},
            group=T.String {},
            to_version=T.String {},
        },
        delete_group=T.Dict {
            action=T.Atom { "delete_group" },
            role=T.String {},
            group=T.String {},
        },
        set_number_per_server=T.Dict {
            action=T.Atom { "set_number_per_server" },
            role=T.String {},
            group=T.String {},
            service=T.String {},
            number_per_server=T.Number {},
        },
        set_servers=T.Dict {
            action=T.Atom { "set_servers" },
            role=T.String {},
            group=T.String {},
            service=T.String {},
            servers=T.List { T.String {} },
        },
        update_action=T.Dict {
            action=T.Atom { "update_action" },
            role=T.String {},
            group=T.String {},
            update_action=T.Enum { "pause", "revert", "resume",
                                   "skip", "ack", "error" },
            [T.Key { "error_message", optional=true }]=T.String {},
        },
    },
}

local STATE = T.Dict {
    [T.Key { "groups", default={} }]=T.Map { T.String {}, T.Dict {
        version=T.String {},
        [T.Key { "update", optional=true }]=T.Any {},
        [T.Key { "auto_update", default=false }]=T.Bool {},
        [T.Key { "last_deployed", default={} }]=
            T.Map { T.String {}, T.Number {} },
        [T.Key { "services" , default={} }]=T.Map { T.String {}, T.Dict {
            service=T.String {},
            servers=T.List { T.String {} },
            number_per_server=T.Number {},
            variables=T.Map { T.String {}, T.Or { T.String {}, T.Number {} } },
        }},
    }},
}

local function check_actions(role, actions)
    local invalid_actions = {}
    local valid_actions = {}
    for timestamp, action in pairs(actions) do
        local status, val, err = T.validate(ACTION, action)
        val.timestamp = tonumber(timestamp)
        if status then
            role.log:debug("action", val, "is valid")
            table.insert(valid_actions, val)
        else
            role.log:invalid("bad action", action, err)
            table.insert(invalid_actions, val)
        end
    end
    table.sort(valid_actions, function(a, b)
        return a.timestamp < b.timestamp
    end)
    table.sort(invalid_actions, function(a, b)
        return a.timestamp < b.timestamp
    end)
    return valid_actions, invalid_actions
end

local function merge_states(role, parents)
    local groups = {}
    for _, parent in pairs(parents) do
        local status, val, err = T.validate(STATE, parent.state)
        if status then
            for group_name, group in pairs(val.groups) do
                local out = groups[group_name]
                if out ~= nil then
                    -- TODO(tailhook) merge other things (version?)
                    for ver, timestamp in pairs(group.last_deployed) do
                        local old_ts = out.last_deployed[ver]
                        if old_ts == nil or old_ts < timestamp then
                            out.last_deployed[ver] = timestamp
                        end
                    end
                else
                    groups[group_name] = func.deepcopy(group)
                end
            end
        else
            for _, e in ipairs(err) do
                role.log:error(
                    'parent state', parent.hash or 'unknown-hash',
                    'from', parent.origin or 'unknown-host',
                    'is invalid:', e)
            end
            error("Can't proceed because role "..role.name.." can be dead")
        end
    end
    local ngroups = func.count_keys(groups)
    if ngroups == 0 then
        role.log:debug("No groups configured")
    else
        role.log:debug(ngroups, "groups found")
    end
    local tmp_state = {
        groups=groups,
    }
    local status, state, err = T.validate(STATE, tmp_state)
    if not status then
        for _, e in ipairs(err) do
            role.log:error('merged state is invalid:', e)
        end
    end
    return state
end

function ACTIONS.create_group(role, action, _, _)
    local button = action.button
    if role.state.groups[button.group_name] then
        role.log:error('group', button.group_name, 'already exists')
    else
        role.log:change('new group', button.group_name)
        role.state.groups[button.group_name] = {
            version=button.version,
        }
    end
end

function ACTIONS.add_daemon(role, action, _, _)
    local button = action.button
    local group = role.state.groups[button.group]
    if not group then
        role.log:error('group', button.group, 'does not exists')
        return
    end
    local services = group.services
    if not services then
        services = {}
        group.services = services
    end
    local log = role.log:sub(button.group)
    if services[button.new_name] ~= nil then
        log:error('group already has service', button.new_name)
        return
    end
    local meta = role.versions[group.version]
    if meta == nil then
        log:error(
            "group has no stable version, can't add a deamon in this case")
        return
    end
    if meta.daemons == nil or meta.daemons[button.service] == nil then
        log:error("group of current version has no daemon", button.service)
        return
    end
    services[button.new_name] = {
        service=button.service,
        servers=button.servers,
        number_per_server=button.number_per_server,
        variables=button.variables,
    }
end

function ACTIONS.enable_auto_update(role, action, _, _)
    local button = action.button
    local group = role.state.groups[button.group]
    if not group then
        role.log:error('group', button.group, 'does not exists')
        return
    end
    group.auto_update = true
end

function ACTIONS.disable_auto_update(role, action, _, _)
    local button = action.button
    local group = role.state.groups[button.group]
    if not group then
        role.log:error('group', button.group, 'does not exists')
        return
    end
    group.auto_update = false
end

function ACTIONS.delete_group(role, action, _, _)
    local button = action.button
    local group = role.state.groups[button.group]
    if not group then
        role.log:error('group', button.group, 'does not exists')
        return
    end
    role.state.groups[button.group] = nil
end

function ACTIONS.force_version(role, action, _, now)
    local button = action.button
    local group = role.state.groups[button.group]
    if not group then
        role.log:error('group', repr.log_repr(button.group), 'does not exists')
        return
    end
    if group.version and group.version ~= button.to_version then
        group.last_deployed[group.version] = now
    end
    if role.versions[button.to_version] == nil then
        role.log:sub(button.group):error("no such version",
            repr.log_repr(button.to_version))
        return
    end
    group.version = button.to_version
    group.update = nil
end

function ACTIONS.start_update(role, action, _, now)
    local button = action.button
    local group = role.state.groups[button.group]
    local log = role.log:sub(button.group)
    if not group then
        log:error('group does not exists')
        return
    end
    if group.update ~= nil then
        log:error('group is still updating')
        return
    end
    if group.version and group.version ~= button.to_version then
        group.last_deployed[group.version] = now
    end
    if role.versions[button.to_version] == nil then
        log:error("no such version", repr.log_repr(button.to_version))
        return
    end
    local pipeline = role.update_pipelines[button.group]
    if not pipeline then
        log:error("can't compute update pipeline")
        return
    end
    log:change("starting update from", group.version,
        "to", button.to_version)
    group.update = update.start(group.version, button.to_version,
        pipeline, now)
end

function ACTIONS.set_servers(role, action, _, _)
    local button = action.button
    local group = role.state.groups[button.group]
    if not group then
        role.log:error('group', button.group, 'does not exists')
        return
    end
    local svc = group.services[button.service]
    if not svc then
        role.log:sub(button.group):error(
            'service', button.service, 'does not exists')
        return
    end
    svc.servers = button.servers
end

function ACTIONS.set_number_per_server(role, action, _, _)
    local button = action.button
    local group = role.state.groups[button.group]
    if not group then
        role.log:error('group', button.group, 'does not exists')
        return
    end
    local svc = group.services[button.service]
    if not svc then
        role.log:sub(button.group):error(
            'service', button.service, 'does not exists')
        return
    end
    svc.number_per_server = button.number_per_server
end

function ACTIONS.update_action(role, action, _, _)
    local button = action.button
    local group = role.state.groups[button.group]
    if not group then
        role.log:error('group', button.group, 'does not exists')
        return
    end
    if role.update_actions == nil then
        role.update_actions = {[button.group]={}}
    elseif role.update_actions[button.group] == nil then
        role.update_actions[button.group] = {}
    end
    table.insert(role.update_actions[button.group], action)
end

local function execute_actions(role, actions, now)
    for timestamp, a in pairs(actions) do
        local aname = a.button.action
        role.log:debug('action', aname)
        local fun = ACTIONS[aname]
        if fun ~= nil then
            -- TODO(tailhook) maybe use xpcall ?
            fun(role, a, timestamp, now)
        else
            role.log:error('action', aname, 'is unknown. Skipped.')
        end
    end

    local status, _, err = T.validate(STATE, role.state)
    if not status then
        for _, e in ipairs(err) do
            role.log:error('state is invalid after executing actions:', e)
        end
    end
end

local function auto_update_versions(role, now)
    for gname, group in pairs(role.state.groups) do
        -- TODO(tailhook) execute smooth updates!!!
        if group.auto_update then
            local nver = role.descending_versions[1]
            if group.version ~= nver then
                role.log:sub(gname):change("Automatic update:",
                    group.version, "-> ", nver)
                group.last_deployed[group.version] = now
                group.version = nver
            end
        end
    end

    local status, _, err = T.validate(STATE, role.state)
    if not status then
        for _, e in ipairs(err) do
            role.log:error('state is invalid after executing updates:', e)
        end
    end
end

local function cleanup(role, now)
    local alive_versions = {}
    for i=1,2 do
        local v = role.descending_versions[i]
        if v ~= nil then
            alive_versions[v] = true
        end
    end

    local deploy_cutoff = now - LAST_DEPLOYED_LIFETIME
    for _, group in pairs(role.state.groups) do

        alive_versions[group.version] = true
        if group.update then
            alive_versions[group.update.source_ver] = true
            alive_versions[group.update.target_ver] = true
        end

        local to_remove = {}
        local last_ver = nil
        local last_ts = nil
        for ver, timestamp in pairs(group.last_deployed or {}) do
            if last_ver == nil or last_ts < timestamp then
                last_ver = ver
                last_ts = timestamp
            end
            if timestamp < deploy_cutoff then
                table.insert(to_remove, ver)
            else
                alive_versions[ver] = true
            end
        end
        for _, v in pairs(to_remove) do
            if v ~= last_ver then
                group.last_deployed[v] = nil
            end
        end
        if last_ver then
            alive_versions[last_ver] = true
        end
    end

    local upload_cutoff = now - LAST_UPLOADED_LIFETIME
    for ver, info in pairs(role.versions) do
        local ts = tonumber(info.timestamp)
        if ts ~= nil and ts * 1000 >= upload_cutoff then
            alive_versions[ver] = true
        end
    end

    role.alive_versions = func.keys(alive_versions)
    table.sort(role.alive_versions,
               function(a, b) return version.compare(b, a) end)

    local status, _, err = T.validate(STATE, role.state)
    if not status then
        for _, e in ipairs(err) do
            role.log:error('state is invalid after executing updates:', e)
        end
    end
end

local function calculate_pipelines(role)
    local update_pipelines = {}
    for group_name, group in pairs(role.state.groups or {}) do
        local services = {}
        for service_name, service in pairs(group.services) do
            local ver = role.versions[group.version]
            local vinfo = ver.daemons[service.service]
            local info = func.copy(vinfo and vinfo.update) or {}
            services[service_name] = info
        end
        local pipeline = update.derive_pipeline(services)
        if pipeline then
            update_pipelines[group_name] = pipeline
        else
            role.log:sub(group_name):error("no valid update pipeline")
        end
    end
    return update_pipelines
end

local function execute_updates(role, now)
    for gname, group in pairs(role.state.groups or {}) do
        if group.update then
            local log = role.log:sub(gname)
            if group.update.step == 'done' then
                group.version = group.update.target_ver
                group.update = nil
            else
                group.update = update.tick(
                    group.update,
                    role.group_actions and role.group_actions[gname] or {},
                    now,
                    log)
            end
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

    role.update_pipelines = calculate_pipelines(role)
    execute_actions(role, role.actions, global_state.now)
    execute_updates(role, global_state.now)
    auto_update_versions(role, global_state.now)
    cleanup(role, global_state.now)
end

return {
    prepare=prepare,
    _check_actions=check_actions,
    _merge_states=merge_states,
}
