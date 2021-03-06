local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe
local versions = require("spec/gen").versions
local buttons = require("spec/gen").buttons
local BASE_TIMESTAMP = require("spec/gen").BASE_TIMESTAMP

local func = require("modules/func")
local version_util = require("modules/version_util")


describe("version_numbers() filter", function()
    test("versions", function()
        assert.are.same({"v1.0", "v1.1"},
            version_util.version_numbers(versions("v1.0", "v1.1")))
    end)
end)

describe("latest_version_button() ", function()
    local valid_versions = func.list_to_set({"v1.0", "v1.1", "v2.0"})
    local ts1 = BASE_TIMESTAMP + 1000
    local ts2 = BASE_TIMESTAMP + 3000

    test("valid version", function()
        buttons = {[ts1]={button={version="v1.1", role='some-role'}}}
        assert.are.same({version="v1.1", timestamp=ts1},
            version_util.latest_version_button(buttons, valid_versions))
    end)

    test("no valid versions", function()
        buttons = {[ts1]={button={version="v1.7", role='some-role'}}}
        assert.is_nil(
            version_util.latest_version_button(buttons, valid_versions))
    end)

    test("two versions", function()
        buttons = {
            [ts1]={button={version="v1.1", role='some-role'}},
            [ts2]={button={version="v1.0", role='some-role'}},
        }
        assert.are.same({version="v1.0", timestamp=ts2},
            version_util.latest_version_button(buttons, valid_versions))
    end)

    test("two versions reverse", function()
        buttons = {
            [ts2]={button={version="v1.0", role='some-role'}},
            [ts1]={button={version="v1.1", role='some-role'}},
        }
        assert.are.same({version="v1.0", timestamp=ts2},
            version_util.latest_version_button(buttons, valid_versions))
    end)

    test("invalid version latest", function()
        buttons = {
            [ts1]={button={version="v1.1", role='some-role'}},
            [ts2]={button={version="v1.7", role='some-role'}},
        }
        assert.are.same({version="v1.1", timestamp=ts1},
            version_util.latest_version_button(buttons, valid_versions))
    end)

    test("invalid version older", function()
        buttons = {
            [ts1]={button={version="v1.7", role='some-role'}},
            [ts2]={button={version="v1.1", role='some-role'}},
        }
        assert.are.same({version="v1.1", timestamp=ts2},
            version_util.latest_version_button(buttons, valid_versions))
    end)
end)

describe("latest_parent_version()", function()
    local valid_versions = func.list_to_set({"v1.0", "v1.1", "v2.0"})
    local ts1 = BASE_TIMESTAMP + 1000
    local ts2 = BASE_TIMESTAMP + 3000

    test("no parents", function()
        local parents = {}
        assert.are.same(nil,
            version_util.latest_parent_version(parents, valid_versions))
    end)

    test("invalid parent", function()
        local parents = {{version="v7.4", version_timestamp=ts1}}
        assert.are.same(nil,
            version_util.latest_parent_version(parents, valid_versions))
    end)

    test("valid parent", function()
        local parents = {{version="v1.1", version_timestamp=ts1}}
        assert.are.same({version="v1.1", timestamp=ts1},
            version_util.latest_parent_version(parents, valid_versions))
    end)

    test("valid and invalid parent", function()
        local parents = {
            {version="v1.1", version_timestamp=ts1},
            {version="v1.7", version_timestamp=ts2},
        }
        assert.are.same({version="v1.1", timestamp=ts1},
            version_util.latest_parent_version(parents, valid_versions))
    end)

    test("valid parents 1", function()
        local parents = {
            {version="v1.1", version_timestamp=ts1},
            {version="v2.0", version_timestamp=ts2},
        }
        assert.are.same({version="v2.0", timestamp=ts2},
            version_util.latest_parent_version(parents, valid_versions))
    end)

    test("valid parents 2", function()
        local parents = {
            {version="v2.0", version_timestamp=ts2},
            {version="v1.1", version_timestamp=ts1},
        }
        assert.are.same({version="v2.0", timestamp=ts2},
            version_util.latest_parent_version(parents, valid_versions))
    end)

    test("valid parents 3", function()
        local parents = {
            {version="v2.0", version_timestamp=ts1},
            {version="v1.1", version_timestamp=ts2},
        }
        assert.are.same({version="v1.1", timestamp=ts2},
            version_util.latest_parent_version(parents, valid_versions))
    end)

end)

describe("split_versions() filter", function()
    test("default generated schedule", function()
        local list, map, params = version_util.split_versions(
            versions("v1.0", "v1.1"))
        assert.are.same({
            {"v1.1", "v1.0"},
            {["v1.1"]={timestamp=1465486490},
             ["v1.0"]={timestamp=1465482890}},
            {project_name='hello',
             scheduler_kind='fancy_thing'},
            }, {list, map, params})
    end)
end)
