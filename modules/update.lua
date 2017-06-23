local package = (...):match("(.-)[^/]+$")
local T = require(package..'trafaret')
local func = require(package..'func')
local repr = require(package..'repr')

local SMOOTH_DEFAULT_SUBSTEPS = 10
local DEFAULT_WARMUP = 5
local MAXIMUM_PAUSED = 1800000  -- revert if paused for 30 min
local EXECUTORS = {}

local CONFIG = T.Map { T.String {}, T.Or {
    T.Dict {
        [T.Key { "mode" }]=T.Or { T.Atom { "run-with-ack" } },
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
        [T.Key { "warmup_sec", default=DEFAULT_WARMUP }]=T.Number {},
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
    [T.Key { "substeps", optional=true }]=T.Number {},
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
    auto=T.Bool {},
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
    local warmup = cfg.warmup_sec or DEFAULT_WARMUP
    if stage ~= nil then
        table.insert(stage.processes, daemon)
        -- predictable order, list is just few items, so is very quick
        table.sort(stage.processes)
        if stage.forward_time < warmup then
            stage.forward_time = warmup
        end
        if stage.backward_time < warmup then
            stage.backward_time = warmup
        end
    else
        stages['quick_restart'] = {
            name="quick_restart",
            forward_mode="time",
            forward_time=warmup,
            backward_mode="time",
            backward_time=warmup,
            processes={daemon},
            before=expand_before(cfg.before, "smooth_restart"),
            after=func.copy(cfg.after) or {},
        }
    end
end

local function add_test_mode(stages, daemon, cfg)
    local stage = stages['test_mode']
    local warmup = cfg.warmup_sec or DEFAULT_WARMUP
    if stage ~= nil then
        table.insert(stage.processes, daemon)
        -- predictable order, list is just few items, so is very quick
        table.sort(stage.processes)
        if stage.forward_time < warmup then
            stage.forward_time = warmup
        end
        if stage.backward_time < warmup then
            stage.backward_time = warmup
        end
    else
        stages['test_mode'] = {
            name="test_mode",
            forward_mode="manual",
            forward_time=warmup,
            backward_mode="time",
            backward_time=warmup,
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
    local warmup = cfg.warmup_sec or DEFAULT_WARMUP
    if stage ~= nil then
        table.insert(stage.processes, daemon)
        -- predictable order, list is just few items, so is very quick
        table.sort(stage.processes)
        if stage.substeps < substeps then
            stage.substeps = substeps
        end
        if stage.forward_time < warmup*substeps then
            stage.forward_time = warmup*substeps
        end
        if stage.backward_time < warmup*substeps then
            stage.backward_time = warmup*substeps
        end
    else
        stages['smooth_restart'] = {
            name="smooth_restart",
            forward_mode="smooth",
            forward_time=warmup*substeps,
            backward_mode="smooth",
            backward_time=warmup*substeps,
            substeps=substeps,
            processes={daemon},
            after=func.copy(cfg.after) or {},
            before=expand_before(cfg.before),
        }
    end
end

local function add_command(stages, cname, cfg)
    if cfg.mode == 'run-with-ack' then
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
            step_ts=now,
            change_ts=now,
            source_ver=state.source_ver,
            target_ver=state.target_ver,
            start_ts=state.start_ts,
            auto=state.auto,
            pipeline=state.pipeline
        }
    else
        log:debug("next step is", state.pipeline[idx+1])
        return {
            step=state.pipeline[idx+1].name,
            direction="forward",
            start_ts=state.start_ts,
            step_ts=now,
            change_ts=now,
            source_ver=state.source_ver,
            target_ver=state.target_ver,
            auto=state.auto,
            pipeline=state.pipeline
        }
    end
end

local function prev_step(state, _, idx, now, log)
    if idx == 1 then
        log:change("revert done")
        return {
            step="revert_done",
            direction="backward",
            step_ts=now,
            change_ts=now,
            source_ver=state.source_ver,
            target_ver=state.target_ver,
            start_ts=state.start_ts,
            auto=state.auto,
            pipeline=state.pipeline
        }
    else
        log:debug("prev step is", state.pipeline[idx-1])
        return {
            step=state.pipeline[idx-1].name,
            direction="backward",
            step_ts=now,
            change_ts=now,
            source_ver=state.source_ver,
            target_ver=state.target_ver,
            start_ts=state.start_ts,
            auto=state.auto,
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

function EXECUTORS.forward_manual(state, step, idx, now, log)
    if state.auto and state.step_ts + step.forward_time < now then
        return next_step(state, step, idx, now, log)
    else
        -- do nothing
        return state
    end
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
        if step_no <= 0 then
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
    if state.step == 'start' then
        return next_step(state, nil, 0, now, log)
    elseif state.step == 'done' or state.step == 'revert_done' then
        log:error("Done step should not be passed to the 'tick' function")
        return nil
    end

    local step, step_idx
    for idx, cstep in ipairs(state.pipeline) do
        if cstep.name == state.step then
            step = cstep
            step_idx = idx
            break
        end
    end
    if step == nil then
        log:error("Step", state.step, "not found")
        return nil
    end
    for _, action in ipairs(actions) do
        local button = action.button
        if button.step == nil or button.step == state.step then
            if button.update_action == 'pause' then
                log:change("pausing update")
                state.pause_ts = now
                state.change_ts = now
                state.direction = 'pause'
            elseif button.update_action == 'resume' then
                log:change("resuming update")
                state.pause_ts = nil
                state.change_ts = now
                state.direction = 'forward'
            elseif button.update_action == 'revert' then
                log:change("reverting update")
                state.pause_ts = nil
                state.change_ts = now
                state.direction = 'backward'
            elseif button.update_action == 'skip' then
                log:change("skipping step", state.step)
                return next_step(state, step, step_idx, now, log)
            elseif button.update_action == 'proceed' then
                local mode = state.direction .. '_mode'
                if step[mode] == 'manual' then
                    log:change("manual step proceeded", state.step)
                    return next_step(state, step, step_idx, now, log)
                else
                    log:error("can't proceed on", state.step)
                end
            elseif button.update_action == 'ack' then
                local mode = state.direction .. '_mode'
                if step[mode] == 'ack' then
                    log:change("acked step", state.step)
                    return next_step(state, step, step_idx, now, log)
                else
                    log:error("can't ack", state.step)
                end
            elseif button.update_action == 'error' then
                local mode = state.direction .. '_mode'
                if step[mode] == 'ack' then
                    log:change("error when acking step",
                        state.step, "error:", button.error_messsage)
                    state.pause_ts = now
                    state.change_ts = now
                    state.direction = 'error'
                    state.error_message = button.error_message
                else
                    log:error("can't ack with error on step", state.step)
                end
            else
                log:error("wrong action", button.update_action,
                    "data", repr.log_repr(action))
            end
        else
            log:error("executing action for step", button.step,
                      "at step", state.step)
        end
    end

    if state.direction == 'pause' or state.direction == 'error' then
        if state.pause_ts - now > MAXIMUM_PAUSED then
            state.direction = 'backward'
            log:change(state.direction, "for too long, reverting")
        else
            return state
        end
    end

    local mode = step[state.direction..'_mode']
    if mode == nil then
        log:error("Step", state.step,
            "mode", mode, "is unimplemented")
        return nil
    end
    local action = state.direction..'_'..mode

    local fun = EXECUTORS[action]
    if fun == nil then
        log:error("Step", state.step,
            "action", action, "is unimplemented")
        return nil
    end
    return fun(state, step, step_idx, now, log)
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

local function start(source, target, pipeline, auto, now)
    return {
        source_ver=source,
        target_ver=target,
        step="start",
        direction="forward",
        start_ts=now,
        step_ts=now,
        change_ts=now,
        pipeline=pipeline,
        auto=auto,
    }
end

local function current(state, config)
    local step, step_idx
    if state.step == "start" or state.step == "revert_done" then
        step_idx = 0
        step = {processes={}}
    elseif state.step == "done" then
        step_idx = #state.pipeline+1
        step = {processes={}}
    else
        for idx, cstep in ipairs(state.pipeline) do
            if cstep.name == state.step then
                step = cstep
                step_idx = idx
                break
            end
        end
    end

    if step == nil then
        error("No step "..state.step.." found")
    end

    local processes = {}
    -- already upgraded processes
    if step_idx > 1 then
        for i = 1, step_idx-1 do
            local cstep = state.pipeline[i]
            for _, svc in ipairs(cstep.processes) do
                local cfg = config[svc]
                if cfg.mode == nil then  -- and not commands
                    processes[svc]={[state.target_ver] = 100}
                end
            end
        end
    end
    -- not yet reached
    if step_idx+1 <= #state.pipeline then
        for i = step_idx+1, #state.pipeline do
            local cstep = state.pipeline[i]
            for _, svc in ipairs(cstep.processes) do
                local cfg = config[svc]
                if cfg.mode == nil then  -- and not commands
                    processes[svc]={[state.source_ver] = 100}
                end
            end
        end
    end
    -- currently upgrading
    if step_idx <= #state.pipeline then
        if step.substeps then
            local percent = math.floor(
                (state.substep or 0) / step.substeps * 100)
            for _, svc in ipairs(step.processes) do
                local cfg = config[svc]
                if cfg.restart == 'smooth' then
                    local mypercent = percent
                    if cfg.test_mode_percent then
                        mypercent = math.max(percent, cfg.test_mode_percent)
                    end
                    processes[svc]={
                        [state.source_ver] = 100 - mypercent,
                        [state.target_ver] = mypercent,
                    }
                else
                    -- new version of both quick-restart processes and
                    -- ad-hoc migration commands
                    processes[svc]={
                        [state.target_ver] = 100,
                    }
                end
            end
        elseif step.name == 'test_mode' then
            for _, svc in ipairs(step.processes) do
                local cfg = config[svc]
                if cfg.test_mode_percent then
                    processes[svc]={
                        [state.source_ver] = 100 - cfg.test_mode_percent,
                        [state.target_ver] = cfg.test_mode_percent,
                    }
                end
            end
        else
            for _, svc in ipairs(step.processes) do
                processes[svc]={[state.target_ver] = 100}
            end
        end
    end

    return processes
end

local function spread(items, num, percentages, seed)
    local result = {}
    local base_nums = {}
    local base_sum = 0
    local want_nums = {}
    local want_sum = 0
    for i = 1, #percentages-1 do
        local base = math.floor(num*percentages[i]/100)
        base_nums[i] = base
        base_sum = base_sum + base
        local want = math.floor(num*#items*percentages[i]/100)
        want_nums[i] = want
        want_sum = want_sum + want
    end
    base_nums[#percentages] = num - base_sum
    want_nums[#percentages] = num*#items - want_sum
    for _, item in pairs(items) do
        result[item] = func.copy(base_nums)
    end
    if base_sum*#items < want_sum then
        local off = seed
        for i = 1, #percentages-1 do
            local diff = want_nums[i] - base_nums[i]*#items
            -- not sure this works well for #percentages > 2
            for j = 0, diff-1 do
                local item = items[((off + j) % #items) + 1]
                result[item][i] = result[item][i] + 1
                result[item][#percentages] = result[item][#percentages] - 1
            end
            off = off + diff
        end
    end
    return result
end

return {
    validate_config=validate_config,
    derive_pipeline=derive_pipeline,
    tick=tick,
    start=start,
    current=current,
    spread=spread,
    STATE=STATE,
}
