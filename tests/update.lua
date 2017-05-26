local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local migrations = require("modules/update")

describe("migrations: check process tree", function()
    test("typical processes", function()
        local processes = {
            db_migrate={
                run_before="test_mode",
            },
            celery={
                kind="temporary_shutdown",
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
        local res, _, err = migrations.validate_config(processes)
        if not res then
            for _, e in pairs(err) do
                print("Validation error:", e)
            end
        end
        assert(res)
        --  assert.is.same(processes, converted)  -- defaults are added
    end)
end)
