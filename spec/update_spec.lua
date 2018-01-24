local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local update = require("modules/update")
local mocks = require("spec/mocks")

describe("updates: typical setup", function()
    local processes = {
        db_migrate={
            mode="run-with-ack",
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
            kind="restart",
            processes={"x"},
            forward_mode="time",
            forward_time=5,
            backward_mode="time",
            backward_time=5,
        }})
    end)

    test("custom", function()
        local ok, cfg, _ = update.validate_config({
            x={restart="quick", warmup_sec=5, stage="late",
               after={"smooth_restart"}},
            y={restart="smooth", warmup_sec=5},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {{
            name="smooth_restart",
            kind="smooth",
            processes={"y"},
            forward_mode="smooth",
            forward_time=50,
            backward_mode="smooth",
            backward_time=50,
            substeps=10,
        }, {
            name="late",
            kind="restart",
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
            kind="restart",
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
                kind="test_mode",
                processes={"yyy"},
                test_mode_percent={yyy=1},
                forward_mode="manual",
                forward_time=5,
                backward_mode="time",
                backward_time=5},
            {name="quick_restart",
                kind="restart",
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
                kind="test_mode",
                processes={"yyy", "zzz"},
                test_mode_percent={yyy=1, zzz=2},
                forward_mode="manual",
                forward_time=8,
                backward_mode="time",
                backward_time=8},
            {name="quick_restart",
                kind="restart",
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
                kind="test_mode",
                processes={"zzz"},
                test_mode_percent={zzz=2},
                forward_mode="manual",
                forward_time=8,
                backward_mode="time",
                backward_time=8},
            {name="quick_restart",
                kind="restart",
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
                kind="test_mode",
                processes={"zzz"},
                test_mode_percent={zzz=2},
                forward_mode="manual",
                forward_time=8,
                backward_mode="time",
                backward_time=8},
            {name="smooth_restart",
                kind="smooth",
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
            ccc={mode="run-with-ack", before={"test_mode"}},
            ddd={restart="smooth", warmup_sec=8, test_mode_percent=2},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {
            {name="cmd_ccc",
                kind="run_once",
                processes={"ccc"},
                forward_mode="ack",
                forward_time=0,
                backward_mode="skip",
                backward_time=0},
            {name="test_mode",
                kind="test_mode",
                processes={"ddd"},
                test_mode_percent={ddd=2},
                forward_mode="manual",
                forward_time=8,
                backward_mode="time",
                backward_time=8},
            {name="smooth_restart",
                kind="smooth",
                processes={"ddd"},
                forward_mode="smooth",
                forward_time=80,
                backward_mode="smooth",
                backward_time=80,
                substeps=10,
            },
        })
    end)
    test("command with ignoring downgrade ack", function()
        local ok, cfg, _ = update.validate_config({
            ccc={mode="run-with-ack",
                 downgrade_mode="run-with-ack-ignoring-errors",
                 before={"test_mode"}},
            ddd={restart="smooth", warmup_sec=8, test_mode_percent=2},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {
            {name="cmd_ccc",
                kind="run_once",
                processes={"ccc"},
                forward_mode="ack",
                forward_downgrade_mode="ack_ignore_errors",
                forward_time=0,
                backward_mode="skip",
                backward_time=0},
            {name="test_mode",
                kind="test_mode",
                processes={"ddd"},
                test_mode_percent={ddd=2},
                forward_mode="manual",
                forward_time=8,
                backward_mode="time",
                backward_time=8},
            {name="smooth_restart",
                kind="smooth",
                processes={"ddd"},
                forward_mode="smooth",
                forward_time=80,
                backward_mode="smooth",
                backward_time=80,
                substeps=10,
            },
        })
    end)
    test("invisible test_mode dependency", function()
        local ok, cfg, _ = update.validate_config({
            ccc={mode="run-with-ack", before={"test_mode"}},
            ddd={restart="smooth", warmup_sec=8},
        })
        assert(ok)
        local stages = update.derive_pipeline(cfg)
        assert.is.same(stages, {
            {name="cmd_ccc",
                kind="run_once",
                processes={"ccc"},
                forward_mode="ack",
                forward_time=0,
                backward_mode="skip",
                backward_time=0},
            {name="smooth_restart",
                kind="smooth",
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
        kind="restart",
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
            source_extra={},
            target_ver='v2',
            target_extra={},
            step="start",
            direction="forward",
            start_ts=1,
            step_ts=1,
            change_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, {}, 100, logger)
        assert.is.same({
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step='quick_restart',
            direction='forward',
            change_ts=100,
            step_ts=100,
            start_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, nstate)
    end)
    test("quick restart", function()
        local logger = mocks.Logger("role")
        local step = {
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step="quick_restart",
            direction="forward",
            start_ts=1,
            step_ts=1,
            change_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }
        -- do nothing
        local nstate = update.tick(step, {}, 2, logger)
        assert.is.same({
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step='quick_restart',
            direction='forward',
            change_ts=1,
            step_ts=1,
            start_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, nstate)
        local nstate2 = update.tick(step, {}, 10000, logger)
        assert.is.same({
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step='done',
            direction='forward',
            change_ts=10000,
            step_ts=10000,
            start_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, nstate2)
    end)
end)

describe("updates: ack ticks with skip downgrade", function()
    local SIMPLE = {
            {name="cmd_ccc",
                kind="run_once",
                processes={"ccc"},
                forward_mode="ack",
                forward_downgrade_mode="skip",
                forward_time=0,
                backward_mode="skip",
                backward_time=0},
            {name="test_mode",
                kind="test_mode",
                processes={"ddd"},
                test_mode_percent={ddd=2},
                forward_mode="manual",
                forward_time=8,
                backward_mode="time",
                backward_time=8},
            {name="smooth_restart",
                kind="smooth",
                processes={"ddd"},
                forward_mode="smooth",
                forward_time=80,
                backward_mode="smooth",
                backward_time=80,
                substeps=10,
            },
    }
    test("start upgrade", function()
        local logger = mocks.Logger("role")
        local nstate = update.tick({
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step="start",
            direction="forward",
            start_ts=1,
            step_ts=1,
            change_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, {}, 100, logger)
        assert.is.same({
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step='cmd_ccc',
            direction='forward',
            change_ts=100,
            step_ts=100,
            start_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, nstate)
        -- nothing
        assert.is.same({
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step='cmd_ccc',
            direction='forward',
            change_ts=100,
            step_ts=100,
            start_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, update.tick(nstate, {}, 100000, logger))
        -- ack
        assert.is.same({
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step='test_mode',
            direction='forward',
            change_ts=100000,
            step_ts=100000,
            start_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, update.tick(nstate, {
            {button={step="cmd_ccc", update_action="ack"}},
        }, 100000, logger))
        -- error
        assert.is.same({
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step='cmd_ccc',
            direction='error',
            pause_ts=100000,
            change_ts=100000,
            step_ts=100,
            start_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, update.tick(nstate, {
            {button={step="cmd_ccc", update_action="error"}},
        }, 100000, logger))
    end)

    test("start downgrade", function()
        local logger = mocks.Logger("role")
        local nstate = update.tick({
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step="start",
            direction="forward",
            downgrade=true,
            start_ts=1,
            step_ts=1,
            change_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, {}, 100, logger)
        local nstate2 = update.tick(nstate, {}, 100, logger)
        assert.is.same({
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step='test_mode',
            direction='forward',
            downgrade=true,
            change_ts=100,
            step_ts=100,
            start_ts=1,
            auto=false,
            pipeline=SIMPLE,
        }, nstate2)
    end)
end)

describe("updates: current", function()
    local SMOOTH = {
        {name="test_mode",
            kind="test_mode",
            processes={"zzz"},
            test_mode_percent={zzz=2},
            forward_mode="manual",
            forward_time=8,
            backward_mode="time",
            backward_time=8},
        {name="smooth_restart",
            kind="smooth",
            processes={"yyy", "zzz"},
            forward_mode="smooth",
            forward_time=80,
            backward_mode="smooth",
            backward_time=80,
            substeps=10,
        },
    }
    local ACK = {
        {name="cmd_db_migration",
            backward_mode="skip",
            backward_time=5,
            forward_mode="ack",
            forward_time=5,
            kind="run_once",
            processes={"db_migration"},
        },
        {name="smooth_restart",
            kind="smooth",
            processes={"yyy", "zzz"},
            forward_mode="smooth",
            forward_time=80,
            backward_mode="smooth",
            backward_time=80,
            substeps=10,
        },
    }
    local function step(name, substep)
        return {
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step=name,
            smooth_step=substep,
            direction="forward",
            start_ts=1,
            step_ts=1,
            change_ts=1,
            auto=false,
            pipeline=SMOOTH,
        }
    end
    local function ack_step(name, substep)
        return {
            source_ver='v1',
            source_extra={},
            target_ver='v2',
            target_extra={},
            step=name,
            smooth_step=substep,
            direction="forward",
            start_ts=1,
            step_ts=1,
            change_ts=1,
            auto=false,
            pipeline=ACK,
        }
    end
    test("quick restart", function()
        assert.are.same({
            zzz={v1=98, v2=2},
            yyy={v1=100, v2=nil},
        }, update.current(step("test_mode")))
        assert.are.same({
            zzz={v1=98, v2=2},
            yyy={v1=100, v2=0},
        }, update.current(step("smooth_restart", 0)))
        assert.are.same({
            zzz={v1=70, v2=30},
            yyy={v1=70, v2=30},
        }, update.current(step("smooth_restart", 3)))
        assert.are.same({
            zzz={v1=0, v2=100},
            yyy={v1=0, v2=100},
        }, update.current(step("smooth_restart", 10)))
        assert.are.same({
            zzz={v1=nil, v2=100},
            yyy={v1=nil, v2=100},
        }, update.current(step("done")))
        assert.are.same({
            zzz={v1=100, v2=nil},
            yyy={v1=100, v2=nil},
        }, update.current(step("revert_done")))
        assert.are.same({
            zzz={v1=100, v2=nil},
            yyy={v1=100, v2=nil},
        }, update.current(step("start")))
    end)
    test("ack", function()
        assert.are.same({
            zzz={v1=100},
            yyy={v1=100},
            db_migration={v1=nil, v2=100},
        }, update.current(ack_step("cmd_db_migration")))
        assert.are.same({
            zzz={v1=100, v2=0},
            yyy={v1=100, v2=0},
            db_migration={v1=nil, v2=nil},
        }, update.current(ack_step("smooth_restart", 0)))
    end)
end)

describe("updates: spread", function()
    test("0/100", function()
        assert.are.same(update.spread({'a', 'b', 'c'}, 7, {0, 100}, 0),
            {a={0, 7}, b={0, 7}, c={0, 7}})
    end)
    test("100/0", function()
        assert.are.same(update.spread({'a', 'b', 'c'}, 7, {100, 0}, 0),
            {a={7, 0}, b={7, 0}, c={7, 0}})
    end)
    test("70/30", function()
        assert.are.same(update.spread({'a', 'b', 'c'}, 7, {70, 30}, 0),
            {a={5, 2}, b={5, 2}, c={4, 3}})
    end)
    test("30/70", function()
        assert.are.same(update.spread({'a', 'b', 'c'}, 7, {30, 70}, 0),
            {a={2, 5}, b={2, 5}, c={2, 5}})
    end)
    test("70/30 + seed", function()
        assert.are.same(update.spread({'a', 'b', 'c'}, 7, {70, 30}, 2),
            {a={5, 2}, b={4, 3}, c={5, 2}})
    end)
end)
