local package = (...):match("(.-)[^/]+$")
local T = require(package..'trafaret')

local CONFIG = T.Map { T.String {}, T.Or {
    T.Dict {
        run_before=T.Or {
            T.Atom { "test_mode" },
        },
    },
    T.Dict {
        kind=T.Or {
            T.Atom { "smooth_alternate_port" },
            T.Atom { "smooth_same_port" },
            T.Atom { "temporary_shutdown" },
            T.Atom { "quick_restart_before_test" },
            T.Atom { "quick_restart" },
            T.Atom { "quick_restart_after" },
        },
        [T.Key { "test_mode_percent", default=0 }]=T.Number {},
        [T.Key { "warmup_sec", default=1 }]=T.Number {},
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

local function derive_pipeline(config)
    local pipeline = {}
    for daemon, cfg in pairs(config) do
        if cfg.kind == "quick_restart" then
            local insert_idx = 1
            local inserted = false
            for idx, s in pairs(pipeline) do
                if s.name == 'quick_restart' then
                    table.insert(s.processes, daemon)
                    if s.forward_time < cfg.warmup_sec then
                        s.forward_time = cfg.warmup_sec
                    end
                    if s.backward_time < cfg.warmup_sec then
                        s.backward_time = cfg.warmup_sec
                    end
                    inserted = true
                    break
                elseif s.name == 'test_mode' then
                    insert_idx = idx+1
                end
            end
            if not inserted then
                table.insert(pipeline, insert_idx, {
                    name="quick_restart",
                    forward_mode="time",
                    forward_time=cfg.warmup_sec,
                    backward_mode="time",
                    backward_time=cfg.warmup_sec,
                    processes={daemon},
                })
            end
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
