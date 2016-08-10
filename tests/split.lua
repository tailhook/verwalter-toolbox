local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe
local gen = require("tests/gen")

local split = require("modules/split")

describe("get_actions", function()
    test("empty", function()
        local schedule = gen.schedule { actions={} }
        assert.are.same({}, split.actions(schedule, "some-role"))
    end)
    test("single", function()
        local schedule = gen.schedule { actions={
            gen.button { role='some-role', version='v0.0.0' },
        }}
        assert.are.same(
            {{button={role='some-role', version='v0.0.0'}}},
            split.actions(schedule, "some-role"))
    end)
    test("filtered out", function()
        local schedule = gen.schedule { actions={
            gen.button { role='some-role', version='v0.0.0' },
            gen.button { role='other-role', version='v1.1.0' },
        }}
        assert.are.same(
            {{button={role='some-role', version='v0.0.0'}}},
            split.actions(schedule, "some-role"))
    end)
end)
