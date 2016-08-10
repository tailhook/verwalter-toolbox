local table = require("table")
local func = require("modules/func")

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
                return BASE_TIMESTAMP + key*7, value
            else
                return key, value
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
    end

    if sched.peers == nil then
        sched.peers = func.map_to_dict(function(_, item)
            return item.id, {hostname=item.hostname}
        end, example_hosts)
    end

    return sched
end

local function button(btn)
    return {button=btn}
end

local function steady_metric(host_index, role, metric, data_points, value)
    return {
        example_hosts[host_index].id,
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

return {
    schedule=schedule,
    button=button,
    steady_metric=steady_metric,
}
