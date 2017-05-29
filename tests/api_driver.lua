local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local api = require("modules/drivers/api")

describe("check_action", function()
    test("actions 1", function()
        local valid, inv =api._check_actions(
            {name="myrole"},
            {
                ["1496068428001"]={button={
                    action="create_group", role="myrole",
                    group_name="gr1", version="v2.3.3"}},
                ["1496068428002"]={button={
                    action="create_group", role="myrole",
                    group_name="gr2", version="v1.1.1"}},
                ["1496068428003"]={button={
                    action="something_bad", role="myrole",
                    group_name="gr2", version="v1.1.1"}},
            })
        assert.are.same(valid, {
            {timestamp=1496068428001,
             button={action="create_group", role="myrole",
                     group_name="gr1", version="v2.3.3"}},
            {timestamp=1496068428002,
             button={action="create_group", role="myrole",
                     group_name="gr2", version="v1.1.1"}},
        })
        assert.are.same(inv, {
            {timestamp=1496068428003,
             button={action="something_bad", role="myrole",
                     group_name="gr2", version="v1.1.1"}},
        })
    end)
end)
