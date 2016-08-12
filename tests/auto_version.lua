local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe
local gen = require("tests/gen")

local auto_version = require("modules/auto_version")


describe("auto_version.select()", function()
    local runtime = gen.versions("v1.0", "v1.1")
    local runtime_new = gen.versions("v1.0", "v1.1", "v2.0")
    local runtime_old = gen.versions("v1.0", "v1.1", "v2.0", "v1.4")
    local v10ts = gen.BASE_TIMESTAMP + 1*3600000
    local v11ts = gen.BASE_TIMESTAMP + 2*3600000
    local v20ts = gen.BASE_TIMESTAMP + 3*3600000
    local ts1 = gen.BASE_TIMESTAMP + 2*3600000 + 10
    local ts2 = gen.BASE_TIMESTAMP + 3*3600000 + 10
    local ts_now = gen.BASE_TIMESTAMP + 5*3600000 + 20

    test("default version", function()
        local _, version = auto_version.select({
            runtime=runtime,
            actions={},
            now=ts_now,
            parents={}
        })
        assert.are.same({version="v1.1", timestamp=v11ts}, version)
    end)

    test("just (two) parents", function()
        local _, version = auto_version.select({
            runtime=runtime,
            actions={},
            now=ts_now,
            parents={
                {version="v1.1", version_timestamp=v11ts},
                {version="v1.0", version_timestamp=v10ts},
            }
        })
        assert.are.same({version="v1.1", timestamp=v11ts}, version)
    end)

    test("button", function()
        local _, version = auto_version.select({
            runtime=runtime,
            actions={[ts2]={button={version="v1.1", role='some-role'}}},
            now=ts_now,
            parents={
                {version="v2.0", version_timestamp=v20ts},
            },
        })
        assert.are.same({version="v1.1", timestamp=ts_now}, version)
    end)

    test("button always overrides", function()
        assert(v20ts > ts1)
        local _, version = auto_version.select({
            runtime=runtime,
            actions={[ts1]={button={version="v1.1", role='some-role'}}},
            now=ts_now,
            parents={
                {version="v2.0", version_timestamp=v20ts},
            },
        })
        assert.are.same({version="v1.1", timestamp=ts_now}, version)
    end)

    test("new version", function()
        local _, version = auto_version.select({
            runtime=runtime_new,
            actions={},
            now=ts_now,
            parents={
                {version="v1.1", version_timestamp=v11ts},
                {version="v1.0", version_timestamp=v10ts},
            }
        })
        assert.are.same({version="v2.0", timestamp=v20ts}, version)
    end)

    test("added old version", function()
        local _, version = auto_version.select({
            runtime=runtime_old,
            actions={},
            now=ts_now,
            parents={
                {version="v1.1", version_timestamp=v11ts},
                {version="v1.0", version_timestamp=v10ts},
            }
        })
        assert.are.same({version="v2.0", timestamp=v20ts}, version)
    end)
end)
