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

describe("get_metrics", function()
    test("empty", function()
        local schedule = gen.schedule { metrics={} }
        assert.are.same({}, split.metrics(schedule, "some-role"))
    end)
    test("single", function()
        local schedule = gen.schedule { metrics={
            gen.steady_metric(1, "some-role", "user_time", 5, 0.0),
        }}
        assert.are.same(
            {host1={user_time={
                type="multi_series",
                items={{
                    key={metric="user_time"},
                    timestamps={1465479290000, 1465479292000, 1465479294000,
                                1465479296000, 1465479298000},
                    values={0.0, 0.0, 0.0, 0.0, 0.0},
                }},
            }}}, split.metrics(schedule, "some-role"))
    end)
    test("filtered out roles", function()
        local schedule = gen.schedule { metrics={
            gen.steady_metric(1, "some-role", "user_time", 5, 0.0),
            gen.steady_metric(1, "other-role", "user_time", 5, 0.0),
        }}
        assert.are.same(
            {host1={user_time={
                type="multi_series",
                items={{
                    key={metric="user_time"},
                    timestamps={1465479290000, 1465479292000, 1465479294000,
                                1465479296000, 1465479298000},
                    values={0.0, 0.0, 0.0, 0.0, 0.0},
                }},
            }}}, split.metrics(schedule, "some-role"))
    end)
end)
