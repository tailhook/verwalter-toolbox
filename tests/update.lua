local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local update = require("modules/update")
local mocks = require("tests/mocks")

describe("updates: typical setup", function()
    local processes = {
        db_migrate={
            mode="run_with_ack",
            before={"test_mode"},
        },
        celery={
            restart="quick",
            before={"test_mode"},
            warmup_sec=5,
        },
        slow_site={
            restart="smooth",
            smooth_mode="alternate_port",
            test_mode_percent=5,
            warmup_sec=15,
        },
        fast_site={
            restart="smooth",
            smooth_mode="same_port",
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
            x={restart="quick", warmup_sec=5}
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
            one={restart="quick", warmup_sec=5},
            two={restart="quick", warmup_sec=7},
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
    test("quick restart with test mode", function()
        local ok, cfg, _ = update.validate_config({
            yyy={restart="quick", warmup_sec=5, test_mode_percent=1},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {
            {name="test_mode",
                processes={"yyy"},
                forward_mode="manual",
                forward_time=5,
                backward_mode="time",
                backward_time=5},
            {name="quick_restart",
                processes={"yyy"},
                forward_mode="time",
                forward_time=5,
                backward_mode="time",
                backward_time=5,
            },
        })
    end)

    test("quick restart with test mode 2", function()
        local ok, cfg, _ = update.validate_config({
            yyy={restart="quick", warmup_sec=5, test_mode_percent=1},
            zzz={restart="quick", warmup_sec=8, test_mode_percent=2},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {
            {name="test_mode",
                processes={"yyy", "zzz"},
                forward_mode="manual",
                forward_time=8,
                backward_mode="time",
                backward_time=8},
            {name="quick_restart",
                processes={"yyy", "zzz"},
                forward_mode="time",
                forward_time=8,
                backward_mode="time",
                backward_time=8,
            },
        })
    end)

    test("quick restart with test mode 1/2", function()
        local ok, cfg, _ = update.validate_config({
            yyy={restart="quick", warmup_sec=5 },
            zzz={restart="quick", warmup_sec=8, test_mode_percent=2},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {
            {name="test_mode",
                processes={"zzz"},
                forward_mode="manual",
                forward_time=8,
                backward_mode="time",
                backward_time=8},
            {name="quick_restart",
                processes={"yyy", "zzz"},
                forward_mode="time",
                forward_time=8,
                backward_mode="time",
                backward_time=8,
            },
        })
    end)

    test("smooth restart", function()
        local ok, cfg, _ = update.validate_config({
            yyy={restart="smooth", warmup_sec=5 },
            zzz={restart="smooth", warmup_sec=8, test_mode_percent=2},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {
            {name="test_mode",
                processes={"zzz"},
                forward_mode="manual",
                forward_time=8,
                backward_mode="time",
                backward_time=8},
            {name="smooth_restart",
                processes={"yyy", "zzz"},
                forward_mode="smooth",
                forward_time=80,
                backward_mode="smooth",
                backward_time=80,
                substeps=10,
            },
        })
    end)

    test("command", function()
        local ok, cfg, _ = update.validate_config({
            ccc={mode="run_with_ack", before={"test_mode"}},
            ddd={restart="smooth", warmup_sec=8, test_mode_percent=2},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {
            {name="cmd_ccc",
                processes={"ccc"},
                forward_mode="ack",
                forward_time=0,
                backward_mode="skip",
                backward_time=0},
            {name="test_mode",
                processes={"ddd"},
                forward_mode="manual",
                forward_time=8,
                backward_mode="time",
                backward_time=8},
            {name="smooth_restart",
                processes={"ddd"},
                forward_mode="smooth",
                forward_time=80,
                backward_mode="smooth",
                backward_time=80,
                substeps=10,
            },
        })
    end)
    test("transient_test_mode", function()
        local ok, cfg, _ = update.validate_config({
            ccc={mode="run_with_ack", before={"test_mode"}},
            ddd={restart="smooth", warmup_sec=8},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {
            {name="cmd_ccc",
                processes={"ccc"},
                forward_mode="ack",
                forward_time=0,
                backward_mode="skip",
                backward_time=0},
            {name="smooth_restart",
                processes={"ddd"},
                forward_mode="smooth",
                forward_time=80,
                backward_mode="smooth",
                backward_time=80,
                substeps=10,
            },
        })
    end)
end)

describe("updates: ticks", function()
    local SIMPLE = {{
        name="quick_restart",
        processes={"x"},
        forward_mode="time",
        forward_time=5,
        backward_mode="time",
        backward_time=5,
    }}
    test("start", function()
        local logger = mocks.Logger("role")
        local nstate = update.tick({
            source_ver='v1',
            target_ver='v2',
            step="start",
            direction="forward",
            start_ts=1,
            step_ts=1,
            change_ts=1,
            pipeline=SIMPLE,
        }, {}, 100, logger)
        assert.is.same({
            source_ver='v1',
            target_ver='v2',
            step='quick_restart',
            direction='forward',
            change_ts=100,
            step_ts=100,
            start_ts=100,
            pipeline=SIMPLE,
        }, nstate)
    end)
    test("quick restart", function()
        local logger = mocks.Logger("role")
        local step = {
            source_ver='v1',
            target_ver='v2',
            step="quick_restart",
            direction="forward",
            start_ts=1,
            step_ts=1,
            change_ts=1,
            pipeline=SIMPLE,
        }
        -- do nothing
        local nstate = update.tick(step, {}, 2, logger)
        assert.is.same({
            source_ver='v1',
            target_ver='v2',
            step='quick_restart',
            direction='forward',
            change_ts=1,
            step_ts=1,
            start_ts=1,
            pipeline=SIMPLE,
        }, nstate)
        local nstate2 = update.tick(step, {}, 10, logger)
        assert.is.same({
            source_ver='v1',
            target_ver='v2',
            step='done',
            direction='forward',
            change_ts=10,
            step_ts=10,
            start_ts=10,
            pipeline=SIMPLE,
        }, nstate2)
    end)
end)
