local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe
local versions = require("tests/gen").versions

local version_util = require("modules/version_util")


describe("version_numbers() filter", function()
    test("versions", function()
        assert.are.same({"v1.0", "v1.1"},
            version_util.version_numbers(versions("v1.0", "v1.1")))
    end)
end)
