local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local update = require("modules/update")

describe("updates: typical setup", function()
    local processes = {
        db_migrate={
            run_before="test_mode",
        },
        celery={
            kind="quick_restart",
            warmup_sec=5,
        },
        slow_site={
            kind="smooth_alternate_port",
            test_mode_percent=5,
            warmup_sec=15,
        },
        fast_site={
            kind="smooth_same_port",
            test_mode_percent=5,
            warmup_sec=1,
        },
    }
    test("validate processes", function()
        local res, _, err = update.validate_config(processes)
        if not res then
            for _, e in pairs(err) do
                print("Validation error:", e)
            end
        end
        assert(res)
        --  assert.is.same(processes, converted)  -- defaults are added
    end)
end)
describe("updates: stages", function()
    test("no processes", function()
        local stages = update.derive_pipeline({})
        assert.is.same(stages, {})
    end)
    test("quick restart", function()
        local ok, cfg, _ = update.validate_config({
            x={kind="quick_restart", warmup_sec=5}
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {{
            name="quick_restart",
            processes={"x"},
            forward_mode="time",
            forward_time=5,
            backward_mode="time",
            backward_time=5,
        }})
    end)

    test("quick restart 2", function()
        local ok, cfg, _ = update.validate_config({
            one={kind="quick_restart", warmup_sec=5},
            two={kind="quick_restart", warmup_sec=7},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {{
            name="quick_restart",
            processes={"one", "two"},
            forward_mode="time",
            forward_time=7,
            backward_mode="time",
            backward_time=7,
        }})
    end)
end)
