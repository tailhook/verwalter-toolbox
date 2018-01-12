
local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local repr = require("modules/repr")

describe("repr: tables", function()
    test("dict", function()
        assert.is.same("{hello=1}", repr.log_repr({hello=1}))
    end)
    test("list", function()
        assert.is.same('{1, 2, 3, "x", "y"}', repr.log_repr({1, 2, 3, "x", "y"}))
    end)
end)
