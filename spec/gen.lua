local table = require("table")
local func = require("modules/func")
local role_module = require("modules/role")

-- just some arbitrary base time
local BASE_TIMESTAMP = 1465479290000
local example_hosts = {
    {id="0d690419cd304aaab59eff4252d24001", hostname="host1"},
    {id="83b26e29eb614c97b623ce5cbb886002", hostname="host2"},
    {id="a0a48b51df67403c988eda77ac89b003", hostname="host3"},
    {id="25b9db39804c46009dd9fb2a405fe004", hostname="host4"},
}

local function schedule(sched)
    sched = func.copy(sched)

    if sched.actions then
        sched.actions = func.map_to_dict(function(key, value)
            if key < 1000000000000 then
                return tostring(BASE_TIMESTAMP + key*7), value
            else
                return tostring(key), value
            end
        end, sched.actions)
    end

    if sched.metrics then
        local metrics = {}
        for host, value in pairs(sched.metrics) do
            if type(host) ~= 'string' then
                host, value = table.unpack(value)
            end
            if metrics[host] then
                for group, values in pairs(value) do
                    if metrics[host][group] == nil then
                        metrics[host][group] = values
                    else
                        error("Merging metrics is not implemented")
                    end
                end
            else
                metrics[host] = value
            end
        end
        sched.metrics = metrics
    else
        sched.metrics = {}
    end

    if sched.peers == nil then
        sched.peers = func.map_to_dict(function(_, item)
            return item.id, {hostname=item.hostname}
        end, example_hosts)
    end

    if sched.parents == nil then
        sched.parents = {}
    end

    if sched.actions == nil then
        sched.actions = {}
    end

    return sched
end

local function button(btn)
    return {button=btn}
end

local function steady_metric(host_id, role, metric, data_points, value)
    if type(host_id) == 'number' then
        host_id = example_hosts[host_id].id
    end
    return {
        host_id,
        {[role..'.'..metric]={
            type="multi_series",
            items={{
                key={metric=metric},
                -- some arbitrary base time
                timestamps=func.range_step_num(BASE_TIMESTAMP,
                                               2000, data_points),
                values=func.repeat_num(value, data_points),
            }}}}}
end

local function versions(...)
    local timestamp = math.floor(BASE_TIMESTAMP/1000)  -- in seconds
    local result = func.map_to_dict(function(_, ver)
        timestamp = timestamp + 3600  -- another version each hour
        -- TODO(tailhook) add some expected metadata
        return ver, {timestamp=timestamp}
    end, {...})
    -- Add some additional keys to filter out
    result.project_name = "hello"
    result.scheduler_kind = "fancy_thing"
    return result
end

local function role(name)
    local x = role_module.from_fields({
        name=name,

        parameters={},
        versions={},
        descending_versions={},

        actions={},
        parents={},
    })
    return x
end

return {
    schedule=schedule,
    button=button,
    steady_metric=steady_metric,
    versions=versions,
    BASE_TIMESTAMP=BASE_TIMESTAMP,
    role=role,
}
