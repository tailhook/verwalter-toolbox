local assert = require('luassert')
local busted = require('busted')
local test = busted.test

local compare = require("modules/version").compare

test("various comparisons", function()
    assert.truthy(compare("v1", "v2"))
    assert.truthy(not compare("v1.0", "v1"))
    assert.truthy(not compare("v2", "v1"))
    assert.truthy(compare("v2", "v10"))
    assert.truthy(compare("v2", "v11"))
    assert.truthy(not compare("v10", "v2"))
    assert.truthy(not compare("v12", "v2"))
    assert.truthy(compare("v1.1", "v2.1"))
    assert.truthy(compare("v2.1", "v2.3"))
    assert.truthy(not compare("v2.3", "v2.1"))
    assert.truthy(compare("v2", "v2.1"))
end)

test("nil comparison", function()
    assert.falsy(compare(nil, nil))
    assert.truthy(compare(nil, "v1"))
    assert.falsy(compare("v1", nil))
end)

-- false for equal versions
test("compare is false for equal versions", function()
    assert.falsy(compare("v1", "v1"))
    assert.falsy(compare("v2", "v2"))
    assert.falsy(compare("v2.3.4", "v2.3.4"))
end)

test("version sort", function()
    local _sorttable = {"v1.1.0", "v1.0", "v2.15", "v3.4.6", "v1", "v2.3",
                        "v1.1", "v10.0"}
    table.sort(_sorttable, compare)
    assert.are.same(_sorttable, {
        "v1",
        "v1.0",
        "v1.1",
        "v1.1.0",
        "v2.3",
        "v2.15",
        "v3.4.6",
        "v10.0",
    })
end)
