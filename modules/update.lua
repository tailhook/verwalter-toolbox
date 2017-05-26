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
        },
        [T.Key { "test_mode_percent", default=0 }]=T.Number {},
        [T.Key { "warmup_sec", default=1 }]=T.Number {},
    },
}}

local function validate_config(config)
    return T.validate(CONFIG, config)
end

return {
    validate_config=validate_config,
}
