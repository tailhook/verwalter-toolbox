local package = (...):match("(.-)[^/]+$")
local T = require(package..'trafaret')
local func = require(package..'func')
local repr = require(package..'repr')

local SMOOTH_DEFAULT_SUBSTEPS = 10
local MAXIMUM_PAUSED = 1800000  -- revert if paused for 30 min
local EXECUTORS = {}

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
        [T.Key { "smooth_substeps", optional=true }]=T.Number {},
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
    [T.Key { "substeps", default=SMOOTH_DEFAULT_SUBSTEPS }]=T.Number {},
}}

local STATE = T.Dict {
    pipeline=PIPELINE,
    source_ver=T.String {},
    target_ver=T.String {},
    step=T.String {},
    direction=T.Enum {"forward", "backward", "pause"},
    start_ts=T.Number {},
    step_ts=T.Number {},
    change_ts=T.Number {},
    [T.Key { "pause_ts", optional=true }]=T.Number {},
    [T.Key { "smooth_step", optional=true }]=T.Number {},
}

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
    local substeps = cfg.smooth_substeps or SMOOTH_DEFAULT_SUBSTEPS
    if stage ~= nil then
        table.insert(stage.processes, daemon)
        -- predictable order, list is just few items, so is very quick
        table.sort(stage.processes)
        if stage.substeps < substeps then
            stage.substeps = substeps
        end
        if stage.forward_time < cfg.warmup_sec*substeps then
            stage.forward_time = cfg.warmup_sec*substeps
        end
        if stage.backward_time < cfg.warmup_sec*substeps then
            stage.backward_time = cfg.warmup_sec*substeps
        end
    else
        stages['smooth_restart'] = {
            name="smooth_restart",
            forward_mode="smooth",
            forward_time=cfg.warmup_sec*substeps,
            backward_mode="smooth",
            backward_time=cfg.warmup_sec*substeps,
            substeps=substeps,
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
            if cfg.test_mode_percent and cfg.test_mode_percent > 0 then
                add_test_mode(stages, daemon, cfg)
            end
        elseif cfg.restart == "smooth" then
            add_smooth_restart(stages, daemon, cfg)
            if cfg.test_mode_percent and cfg.test_mode_percent > 0 then
                add_test_mode(stages, daemon, cfg)
            end
        elseif cfg.mode ~= nil then
            add_command(stages, daemon, cfg)
        else
            print("Error, can't classify daemon", daemon,
                ". Treating it as a restart='quick'")
            add_quick_restart(stages, daemon, {
                restart="quick",
                warmup_sec=5,
            })
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

local function next_step(state, _, idx, now, log)
    if idx >= #state.pipeline then
        log:debug("update done at step", idx)
        return {
            step="done",
            direction="forward",
            start_ts=now,
            step_ts=now,
            change_ts=now,
            source_ver=state.source_ver,
            target_ver=state.target_ver,
            pipeline=state.pipeline
        }
    else
        log:debug("next step is", state.pipeline[idx+1])
        return {
            step=state.pipeline[idx+1].name,
            direction="forward",
            start_ts=now,
            step_ts=now,
            change_ts=now,
            source_ver=state.source_ver,
            target_ver=state.target_ver,
            pipeline=state.pipeline
        }
    end
end

local function prev_step(state, _, idx, now, log)
    if idx == 1 then
        log:debug("revert done")
        return {
            step="done",
            direction="backward",
            start_ts=now,
            step_ts=now,
            change_ts=now,
            source_ver=state.source_ver,
            target_ver=state.target_ver,
            pipeline=state.pipeline
        }
    else
        log:debug("prev step is", state.pipeline[idx-1])
        return {
            step=state.pipeline[idx-1].name,
            direction="backward",
            start_ts=now,
            step_ts=now,
            change_ts=now,
            source_ver=state.source_ver,
            target_ver=state.target_ver,
            pipeline=state.pipeline
        }
    end
end

function EXECUTORS.forward_time(state, step, idx, now, log)
    if state.step_ts + step.forward_time < now then
        return next_step(state, step, idx, now, log)
    else
        -- do nothing
        return state
    end
end

function EXECUTORS.backward_time(state, step, idx, now, log)
    if state.step_ts + step.backward_time < now then
        return prev_step(state, step, idx, now, log)
    else
        -- do nothing
        return state
    end
end

function EXECUTORS.forward_manual(state, _, _, _, _)
    return state
end

function EXECUTORS.forward_ack(state, _, _, _, _)
    return state
end

function EXECUTORS.backward_manual(state, _, _, _, _)
    return state
end

function EXECUTORS.backward_ack(state, _, _, _, _)
    return state
end

function EXECUTORS.forward_smooth(state, step, idx, now, log)
    local step_no = state.smooth_step or 0
    if state.change_ts + (step.forward_time / step.substeps) < now then
        state.change_ts = now
        if step_no >= step.substeps then
            return next_step(state, step, idx, now, log)
        end
        state.smooth_step = step_no + 1
        return state
    else
        return state
    end
end

function EXECUTORS.backward_smooth(state, step, idx, now, log)
    local step_no = state.smooth_step or 0
    if state.change_ts + (step.backward_time / step.substeps) < now then
        state.change_ts = now
        if step_no >= step.substeps then
            return prev_step(state, step, idx, now, log)
        end
        state.smooth_step = step_no - 1
        return state
    else
        return state
    end
end

function EXECUTORS.backward_skip(state, step, idx, now, log)
    return prev_step(state, step, idx, now, log)
end

local function internal_tick(state, actions, now, log)
    for _, action in ipairs(actions) do
        log:debug("unimplemented actions", repr.log_repr(action))
    end
    if state.direction == 'paused' then
        if state.pause_ts - now > MAXIMUM_PAUSED then
            state.direction = 'backwards'
            log:change("paused for too long, reverting")
        else
            return state
        end
    end
    if state.step == 'start' then
        return next_step(state, nil, 0, now, log)
    elseif state.step == 'done' then
        log:error("Done step should not be passed to the 'tick' function")
        return nil
    end
    for idx, step in ipairs(state.pipeline) do
        if step.name == state.step then
            local action = state.direction..'_'..step.forward_mode

            local fun = EXECUTORS[action]
            if fun == nil then
                log:error("Step", state.step,
                    "action", action, "is unimplemented")
                return nil
            end
            return fun(state, step, idx, now, log)
        end
    end
    log:error("Step", state.step, "not found")
    return nil
end

local function tick(input, actions, now, log)
    local ok, state, err = T.validate(STATE, input)
    if not ok then
        log:invalid("update state error", input, err)
        return nil
    end

    local nstate = internal_tick(state, actions, now, log)

    if nstate == nil then
        log:change("forcing revert, sorry")
        return nil
    end
    local ok2, result, err2 = T.validate(STATE, nstate)
    if not ok2 then
        log:invalid("bad state after update", nstate, err2)
        log:change("forcing revert, sorry")
        return nil
    end

    return result
end

local function start(source, target, pipeline, now)
    return {
        source_ver=source,
        target_ver=target,
        step="start",
        direction="forward",
        start_ts=now,
        step_ts=now,
        change_ts=now,
        pipeline=pipeline,
    }
end

return {
    validate_config=validate_config,
    derive_pipeline=derive_pipeline,
    tick=tick,
    start=start,
    STATE=STATE,
}
