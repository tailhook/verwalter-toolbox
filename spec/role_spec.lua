local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe
local gen = require("spec/gen")

local role = require("modules/role")

describe("state by role", function()
    local function noop_driver()
        return {
            prepare=function(_) end,
        }
    end
    test("two roles", function()
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
                   name='other_role',
                   log={prefix='', role_name='other_role'},
                },
                some_role={
                   name='some_role',
                   log={prefix='', role_name='some_role'},
                },
            }, role.from_state { schedule, driver=noop_driver })
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
                        version_info={},
                        images={},
                    },
                    y={
                        frontend={kind="api"},
                        versions={},
                        version_info={},
                        images={},
                    },
                },
                state={ },
            })
    end)
end)
