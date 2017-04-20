local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local log = require("modules/log")

describe("log: wrap scheduler", function()
    test("normal_output", function()
        local data, output = log.wrap_scheduler(function()
            return "{}"
        end)({})
        assert.is.same(data, "{}")
        assert.is.same(output, "")
    end)
    test("print", function()
        local data, output = log.wrap_scheduler(function()
            print("hello")
            return "{}"
        end)({})
        assert.is.same(data, "{}")
        assert.is.same(output,
            "[no-role]:DEBUG: hello\n")
    end)
    test("error", function()
        local data, output = log.wrap_scheduler(function()
            local x = {}
            local function test_subfunction()
                x.call_non_existent_method()
            end
            test_subfunction()
            return "{}"
        end)({})
        assert.is.same(data, nil)
        assert(output:find("attempt to call a nil value"))
        assert(output:find("in local 'test_subfunction'"))
    end)
end)
