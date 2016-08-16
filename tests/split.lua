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
            {[1465479290007]={button={role='some-role', version='v0.0.0'}}},
            split.actions(schedule, "some-role"))
    end)
    test("filtered out", function()
        local schedule = gen.schedule { actions={
            gen.button { role='some-role', version='v0.0.0' },
            gen.button { role='other-role', version='v1.1.0' },
        }}
        assert.are.same(
            {[1465479290007]={button={role='some-role', version='v0.0.0'}}},
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

describe("state by role", function()

    -- TODO(tailhook) do something with unconfigured roles
    test("empty config", function()
        local schedule = gen.schedule {
            runtime={
                ['some-role']=gen.versions('v1.0', 'v2.0'),
                ['other-role']=gen.versions('v2.1', 'v3.1'),
            },
            parents={
                gen.schedule {state={['some-role']={version='v1.0'}}},
                gen.schedule {state={['other-role']={version='v1.1'}}},
            }}
        assert.are.same({}, split.state_by_role(schedule, {}))
    end)

    -- TODO(tailhook) do something with unconfigured roles
    test("empty runtime", function()
        local schedule = gen.schedule {
            runtime={},
            parents={
                gen.schedule {state={['some-role']={version='v1.0'}}},
                gen.schedule {state={['other-role']={version='v1.1'}}},
            }}
        assert.are.same({awesome_role={
            actions={},
            daemons={},
            descending_versions={},
            metrics={},
            parameters={},
            parents={},
            peers=schedule.peers,
            role='awesome_role',
            runtime={},
            versions={},
            }}, split.state_by_role(schedule, {
                awesome_role={runtime='some-role', daemons={}}
            }))

    end)

    test("some_config", function()
        local ts1 = 1465482890
        local ts2 = 1465486490
        local schedule = gen.schedule {
            actions={
                gen.button { role='awesome_role', version='v1.0' },
            },
            runtime={
                ['some-role']=gen.versions('v1.0', 'v2.0'),
                ['other-role']=gen.versions('v2.1', 'v3.1'),
            },
            parents={
                gen.schedule {state={['some-role']={version='v1.0'}}},
                gen.schedule {state={['other-role']={version='v1.1'}}},
            }}
        assert.are.same({
                awesome_role={
                   actions={
                       [1465479290007]={button=
                            {role='awesome_role', version='v1.0'}},
                   },
                   daemons={},
                   metrics={},
                   parameters={
                     project_name='hello',
                     scheduler_kind='fancy_thing'},
                   parents={},
                   role='awesome_role',
                   runtime={
                      project_name='hello',
                      scheduler_kind='fancy_thing',
                      ['v2.0']={timestamp=ts2},
                      ['v1.0']={timestamp=ts1},
                   },
                   versions={
                      ['v2.0']={timestamp=ts2},
                      ['v1.0']={timestamp=ts1},
                   },
                   descending_versions={'v2.0', 'v1.0'},
                   peers = schedule.peers,
                },
                other_role={
                   actions={},
                   daemons={},
                   metrics={},
                   parameters={
                    project_name='hello',
                    scheduler_kind='fancy_thing'},
                   parents={},
                   role='other_role',
                   runtime={
                      project_name='hello',
                      scheduler_kind='fancy_thing',
                      ['v3.1']={timestamp=ts2},
                      ['v2.1']={timestamp=ts1},
                   },
                   versions={
                      ['v3.1']={timestamp=ts2},
                      ['v2.1']={timestamp=ts1},
                   },
                   descending_versions={'v3.1', 'v2.1'},
                   peers = schedule.peers,
                },
                another_role={
                   actions={},
                   daemons={},
                   metrics={},
                   parameters={
                    project_name='hello',
                    scheduler_kind='fancy_thing'},
                   parents={},
                   role='another_role',
                   runtime={
                      project_name='hello',
                      scheduler_kind='fancy_thing',
                      ['v3.1']={timestamp=ts2},
                      ['v2.1']={timestamp=ts1},
                   },
                   versions={
                      ['v3.1']={timestamp=ts2},
                      ['v2.1']={timestamp=ts1},
                   },
                   descending_versions={'v3.1', 'v2.1'},
                   peers = schedule.peers,
                },
            }, split.state_by_role(schedule, {
                awesome_role={runtime='some-role', daemons={}},
                other_role={runtime='other-role', daemons={}},
                another_role={runtime='other-role', daemons={}},
            }))
    end)
end)
