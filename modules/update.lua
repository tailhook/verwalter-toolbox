local package = (...):match("(.-)[^/]+$")
local T = require(package..'trafaret')

local SMOOTH_STAGES = 10

local CONFIG = T.Map { T.String {}, T.Or {
    T.Dict {
        run_before=T.List { T.String {} },
        [T.Key { "ack", default=true }]=T.Number {},
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
        -- [T.Key { "after", optional=true }]=T.String {},
    },
}}

local PIPELINE = T.List { T.Dict {
    name=T.String {},
    [T.Key { "forward_mode" }]=
        T.Or { T.Atom { "manual" }, T.Atom { "time" }, T.Atom { "smooth" } },
    [T.Key { "forward_time", default=5 }]=T.Number {},
    [T.Key { "backward_mode" }]=
        T.Or { T.Atom { "manual" }, T.Atom { "time" }, T.Atom { "smooth" } },
    [T.Key { "backward_time", default=5 }]=T.Number {},
    [T.Key { "processes", default={} }]=T.List { T.String {} },
}}

local function validate_config(config)
    return T.validate(CONFIG, config)
end

local function add_quick_restart(pipeline, daemon, cfg)
    local insert_idx = 1
    for idx, s in pairs(pipeline) do
        if s.name == 'quick_restart' then
            table.insert(s.processes, daemon)
            -- predictable order, list is just few items, so is very quick
            table.sort(s.processes)
            if s.forward_time < cfg.warmup_sec then
                s.forward_time = cfg.warmup_sec
            end
            if s.backward_time < cfg.warmup_sec then
                s.backward_time = cfg.warmup_sec
            end
            return
        elseif s.name == 'test_mode' then
            insert_idx = idx+1
        end
    end
    table.insert(pipeline, insert_idx, {
        name="quick_restart",
        forward_mode="time",
        forward_time=cfg.warmup_sec,
        backward_mode="time",
        backward_time=cfg.warmup_sec,
        processes={daemon},
    })
end

local function add_test_mode(pipeline, daemon, cfg)
    for _, s in pairs(pipeline) do
        if s.name == 'test_mode' then
            table.insert(s.processes, daemon)
            -- predictable order, list is just few items, so is very quick
            table.sort(s.processes)
            if s.forward_time < cfg.warmup_sec then
                s.forward_time = cfg.warmup_sec
            end
            if s.backward_time < cfg.warmup_sec then
                s.backward_time = cfg.warmup_sec
            end
            return
        end
    end
    table.insert(pipeline, 1, {
        name="test_mode",
        forward_mode="manual",
        forward_time=cfg.warmup_sec,
        backward_mode="time",
        backward_time=cfg.warmup_sec,
        processes={daemon},
    })
end

local function add_smooth_restart(pipeline, daemon, cfg)
    local insert_idx = 1
    for idx, s in pairs(pipeline) do
        if s.name == 'smooth_restart' then
            table.insert(s.processes, daemon)
            -- predictable order, list is just few items, so is very quick
            table.sort(s.processes)
            if s.forward_time < cfg.warmup_sec*SMOOTH_STAGES then
                s.forward_time = cfg.warmup_sec*SMOOTH_STAGES
            end
            if s.backward_time < cfg.warmup_sec*SMOOTH_STAGES then
                s.backward_time = cfg.warmup_sec*SMOOTH_STAGES
            end
            return
        elseif s.name == 'test_mode' or s.name == 'quick_restart' then
            if idx + 1 > insert_idx then
                insert_idx = idx+1
            end
        end
    end
    table.insert(pipeline, insert_idx, {
        name="smooth_restart",
        forward_mode="smooth",
        forward_time=cfg.warmup_sec*SMOOTH_STAGES,
        backward_mode="smooth",
        backward_time=cfg.warmup_sec*SMOOTH_STAGES,
        processes={daemon},
    })
end

local function derive_pipeline(config)
    local pipeline = {}
    for daemon, cfg in pairs(config) do
        if cfg.restart == "quick" then
            add_quick_restart(pipeline, daemon, cfg)
            if cfg.test_mode_percent > 0 then
                add_test_mode(pipeline, daemon, cfg)
            end
        elseif cfg.restart == "smooth" then
            add_smooth_restart(pipeline, daemon, cfg)
            if cfg.test_mode_percent > 0 then
                add_test_mode(pipeline, daemon, cfg)
            end
        -- else
            -- TODO(tailhook) this is migration/onetime commands
        end
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
