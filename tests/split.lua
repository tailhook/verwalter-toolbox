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
    test("unknown peer", function()
        local schedule = gen.schedule { metrics={
            gen.steady_metric("56b9db39814c46009dd9fb2a405fe099",
                              "some-role", "user_time", 5, 0.0),
        }}
        assert.are.same(
            {}, split.metrics(schedule, "some-role"))
    end)
end)

describe("get_states", function()
    test("empty", function()
        local schedule = gen.schedule {}
        assert.are.same({}, split.states(schedule, "some-role"))
    end)
    test("no role 1", function()
        local schedule = gen.schedule {parents={
            gen.schedule {},
        }}
        assert.are.same({}, split.states(schedule, "some-role"))
    end)
    test("no role 2", function()
        local schedule = gen.schedule {parents={
            gen.schedule {},
            gen.schedule {},
        }}
        assert.are.same({}, split.states(schedule, "some-role"))
    end)
    test("single", function()
        local schedule = gen.schedule {parents={
            gen.schedule {state={['some-role']={version='v1.0'}}},
        }}
        assert.are.same({{version='v1.0'}},
                        split.states(schedule, "some-role"))
    end)
    test("two", function()
        local schedule = gen.schedule {parents={
            gen.schedule {state={['some-role']={version='v1.0'}}},
            gen.schedule {state={['some-role']={version='v1.1'}}},
        }}
        assert.are.same({{version='v1.0'}, {version='v1.1'}},
                        split.states(schedule, "some-role"))
    end)
    test("one of two", function()
        local schedule = gen.schedule {parents={
            gen.schedule {state={['some-role']={version='v1.0'}}},
            gen.schedule {state={['other-role']={version='v1.1'}}},
        }}
        assert.are.same({{version='v1.0'}},
                        split.states(schedule, "some-role"))
    end)
    test("other roles", function()
        local schedule = gen.schedule {parents={
            gen.schedule {state={
                ['some-role']={version='v7.4'},
                ['other-role']={version='v2.0'},
                }},
            gen.schedule {state={['other-role']={version='v1.1'}}},
        }}
        assert.are.same({{version='v7.4'}},
                        split.states(schedule, "some-role"))
    end)
end)
