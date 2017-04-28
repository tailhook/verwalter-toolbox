local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe
local gen = require("tests/gen")

local role = require("modules/role")

describe("state by role", function()
    test("two roles", function()
        local ts1 = 1465482890
        local ts2 = 1465486490
        local schedule = gen.schedule {
            actions={
                gen.button { role='other_role', version='v1.0' },
            },
            runtime={
                ['some_role']=gen.versions('v1.0', 'v2.0'),
                ['other_role']=gen.versions('v2.1', 'v3.1'),
            },
            parents={
                gen.schedule {state={['some_role']={version='v1.0'}}},
                gen.schedule {state={['other_role']={version='v1.1'}}},
            }}
        assert.are.same({
                other_role={
                   actions={
                       ['1465479290007']={button=
                            {role='other_role', version='v1.0'}},
                   },
                   parameters={
                    project_name='hello',
                    scheduler_kind='fancy_thing'},
                   parents={{state={version="v1.1"}}},
                   name='other_role',
                   versions={
                      ['v3.1']={timestamp=ts2},
                      ['v2.1']={timestamp=ts1},
                   },
                   descending_versions={'v3.1', 'v2.1'},
                },
                some_role={
                   actions={},
                   parameters={
                    project_name='hello',
                    scheduler_kind='fancy_thing'},
                   parents={{state={version="v1.0"}}},
                   name='some_role',
                   versions={
                      ['v2.0']={timestamp=ts2},
                      ['v1.0']={timestamp=ts1},
                   },
                   descending_versions={'v2.0', 'v1.0'},
                },
            }, role.from_state(schedule))
    end)
end)

describe("merge output", function()
    test("two roles", function()
        assert.are.same(
            role.merge_output({x=gen.role('x'), y=gen.role('y')}),
            {
                nodes={},
                roles={
                    x={
                        frontend={kind="api"},
                        versions={},
                    },
                    y={
                        frontend={kind="api"},
                        versions={},
                    },
                },
                state={
                    x={},
                    y={},
                },
            })
    end)
end)
