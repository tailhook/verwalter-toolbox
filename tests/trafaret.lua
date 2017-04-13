local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local T = require("modules/trafaret")


describe("trafaret: number", function()
    local number = T.Number{}
    test("validate num", function()
        assert(T.validate(number, 1))
    end)
    test("validate string", function()
        local res, val, err = T.validate(number, "hello")
        assert(not res)
        assert.is.same(val, nil)
        assert.is.same(err, {": Value is not a number, but string"})
    end)
    test("validate table", function()
        local res, val, err = T.validate(number, {})
        assert(not res)
        assert.is.same(val, nil)
        assert.is.same(err, {": Value is not a number, but table"})
    end)
end)
