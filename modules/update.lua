local package = (...):match("(.-)[^/]+$")
local T = require(package..'trafaret')
local func = require(package..'func')

local SMOOTH_STAGES = 10

local CONFIG = T.Map { T.String {}, T.Or {
    T.Dict {
        [T.Key { "mode" }]=T.Or { T.Atom { "run_with_ack" } },
        [T.Key { "duration", default=0 }]=T.Number {},
        [T.Key { "before", optional=true }]=T.List { T.String {} },
        [T.Key { "after", optional=true }]=T.List { T.String {} },
    },
    T.Dict {
        restart=T.Or {
            T.Atom { "smooth" },
            T.Atom { "quick" },
            -- T.Atom { "temporary_shutdown" },
        },
        [T.Key { "test_mode_percent", default=0 }]=T.Number {},
        [T.Key { "warmup_sec", default=1 }]=T.Number {},
        [T.Key { "smooth_mode", optional=true }]=T.String {},
        [T.Key { "before", optional=true }]=T.List { T.String {} },
        [T.Key { "after", optional=true }]=T.List { T.String {} },
    },
}}

local PIPELINE = T.List { T.Dict {
    name=T.String {},
    [T.Key { "forward_mode" }]=
        T.Or { T.Atom { "manual" }, T.Atom { "time" }, T.Atom { "smooth" },
               T.Atom { "ack" }},
    [T.Key { "forward_time", default=5 }]=T.Number {},
    [T.Key { "backward_mode" }]=
        T.Or { T.Atom { "manual" }, T.Atom { "time" }, T.Atom { "smooth" },
               T.Atom { "skip" } },
    [T.Key { "backward_time", default=5 }]=T.Number {},
    [T.Key { "processes", default={} }]=T.List { T.String {} },
}}

local function validate_config(config)
    return T.validate(CONFIG, config)
end

local function expand_before(before, ...)
    if before == nil then
        return {...}
    end
    local result = func.copy(before)
    for _, item in pairs(before) do
        -- adding implicit dependencies
        if item == 'test_mode' then
            table.insert(result, "quick_restart")
            table.insert(result, "smooth_restart")
        end
    end
    for _, item in pairs({...}) do
        table.insert(result, item)
    end
    return result
end

local function add_quick_restart(stages, daemon, cfg)
    local stage = stages['quick_restart']
    if stage ~= nil then
        table.insert(stage.processes, daemon)
        -- predictable order, list is just few items, so is very quick
        table.sort(stage.processes)
        if stage.forward_time < cfg.warmup_sec then
            stage.forward_time = cfg.warmup_sec
        end
        if stage.backward_time < cfg.warmup_sec then
            stage.backward_time = cfg.warmup_sec
        end
    else
        stages['quick_restart'] = {
            name="quick_restart",
            forward_mode="time",
            forward_time=cfg.warmup_sec,
            backward_mode="time",
            backward_time=cfg.warmup_sec,
            processes={daemon},
            before=expand_before(cfg.before, "smooth_restart"),
            after=func.copy(cfg.after) or {},
        }
    end
end

local function add_test_mode(stages, daemon, cfg)
    local stage = stages['test_mode']
    if stage ~= nil then
        table.insert(stage.processes, daemon)
        -- predictable order, list is just few items, so is very quick
        table.sort(stage.processes)
        if stage.forward_time < cfg.warmup_sec then
            stage.forward_time = cfg.warmup_sec
        end
        if stage.backward_time < cfg.warmup_sec then
            stage.backward_time = cfg.warmup_sec
        end
    else
        stages['test_mode'] = {
            name="test_mode",
            forward_mode="manual",
            forward_time=cfg.warmup_sec,
            backward_mode="time",
            backward_time=cfg.warmup_sec,
            processes={daemon},
            before=expand_before(cfg.before,
                        -- implicit before
                        "quick_restart", "smooth_restart"),
            after=func.copy(cfg.after) or {},
        }
    end
end

local function add_smooth_restart(stages, daemon, cfg)
    local stage = stages['smooth_restart']
    if stage ~= nil then
        table.insert(stage.processes, daemon)
        -- predictable order, list is just few items, so is very quick
        table.sort(stage.processes)
        if stage.forward_time < cfg.warmup_sec*SMOOTH_STAGES then
            stage.forward_time = cfg.warmup_sec*SMOOTH_STAGES
        end
        if stage.backward_time < cfg.warmup_sec*SMOOTH_STAGES then
            stage.backward_time = cfg.warmup_sec*SMOOTH_STAGES
        end
    else
        stages['smooth_restart'] = {
            name="smooth_restart",
            forward_mode="smooth",
            forward_time=cfg.warmup_sec*SMOOTH_STAGES,
            backward_mode="smooth",
            backward_time=cfg.warmup_sec*SMOOTH_STAGES,
            processes={daemon},
            after=func.copy(cfg.after) or {},
            before=expand_before(cfg.before),
        }
    end
end

local function add_command(stages, cname, cfg)
    if cfg.mode == 'run_with_ack' then
        local name = 'cmd_'..cname
        stages[name] = {
            name=name,
            forward_mode="ack",
            forward_time=cfg.duration,
            backward_mode="skip",
            backward_time=cfg.duration,
            processes={cname},
            after=func.copy(cfg.after) or {},
            before=expand_before(cfg.before),
        }
    else
        print("Error, can't classify command", cname)
    end
end

local function propagate_constraints(stages)
    for _, stage in pairs(stages) do
        local before = stage.before
        if before ~= nil then
            for _, cname in pairs(before) do
                local cstage = stages[cname]
                if cstage ~= nil then
                    -- duplicates are ok
                    table.insert(cstage.after, stage.name)
                end
            end
        end

        local after = stage.after
        if after ~= nil then
            for _, cname in pairs(after) do
                local cstage = stages[cname]
                if cstage ~= nil then
                    -- duplicates are ok
                    table.insert(cstage.before, stage.name)
                end
            end
        end
    end
end

local function topology_sort(stages)
    local result = {}
    local visited = {}
    local left = func.count_keys(stages)
    while left > 0 do
        local inserted_stages = 0
        for sname, stage in pairs(stages) do
            assert(stage.name == sname)
            if not visited[sname] then
                local can_be_inserted = true
                for _, a in pairs(stage.after or {}) do
                    if visited[a] == nil and stages[a] ~= nil then
                        can_be_inserted = false
                        break
                    end
                end
                if can_be_inserted then
                    table.insert(result, stage)
                    visited[stage.name] = true
                    left = left - 1
                    inserted_stages = inserted_stages + 1
                end
            end
        end
        if inserted_stages == 0 then
            print("Topology cycle between:",
                table.concat(func.keys(stages), ", "))
            return nil
        end
    end
    return result
end

local function derive_pipeline(config)
    local stages = {}
    for daemon, cfg in pairs(config) do
        if cfg.restart == "quick" then
            add_quick_restart(stages, daemon, cfg)
            if cfg.test_mode_percent > 0 then
                add_test_mode(stages, daemon, cfg)
            end
        elseif cfg.restart == "smooth" then
            add_smooth_restart(stages, daemon, cfg)
            if cfg.test_mode_percent > 0 then
                add_test_mode(stages, daemon, cfg)
            end
        elseif cfg.mode ~= nil then
            add_command(stages, daemon, cfg)
        else
            print("Error, can't classify daemon", daemon)
        end
    end
    propagate_constraints(stages)
    local pipeline = topology_sort(stages)
    if pipeline == nil then
        return nil
    end

    -- cleanup already applied constraints
    for _, item in pairs(pipeline) do
        item.before = nil
        item.after = nil
    end

    local ok, result, err = T.validate(PIPELINE, pipeline)
    if not ok then
        for _, e in pairs(err) do
            print("Pipeline validation error", e)
        end
    end
    return result
end

return {
    validate_config=validate_config,
    derive_pipeline=derive_pipeline,
}
