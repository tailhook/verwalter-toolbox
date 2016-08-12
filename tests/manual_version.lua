local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe
-- local buttons = require("tests/gen").buttons
local gen = require("tests/gen")

-- local func = require("modules/func")
local manual_version = require("modules/manual_version")


describe("manual_version.select()", function()
    local runtime = gen.versions("v1.0", "v1.1", "v2.0")
    local ts1 = gen.BASE_TIMESTAMP + 1000
    local ts2 = gen.BASE_TIMESTAMP + 3000

    test("default version", function()
        local _, version = manual_version.select({
            runtime=runtime,
            actions={},
            parents={}
        })
        assert.are.same({version="v2.0", timestamp=0}, version)
    end)

    test("just (two) parents", function()
        local _, version = manual_version.select({
            runtime=runtime,
            actions={},
            parents={
                {version="v2.0", version_timestamp=ts1},
                {version="v1.1", version_timestamp=ts2},
            }
        })
        assert.are.same({version="v1.1", timestamp=ts2}, version)
    end)

    test("button", function()
        local _, version = manual_version.select({
            runtime=runtime,
            actions={[ts2]={button={version="v1.1", role='some-role'}}},
            parents={
                {version="v2.0", version_timestamp=ts1},
            }
        })
        assert.are.same({version="v1.1", timestamp=ts2}, version)
    end)

    test("button late", function()
        local _, version = manual_version.select({
            runtime=runtime,
            actions={[ts1]={button={version="v1.1", role='some-role'}}},
            parents={
                {version="v2.0", version_timestamp=ts2},
            },
        })
        assert.are.same({version="v2.0", timestamp=ts2}, version)
    end)
end)
