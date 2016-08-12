local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe
local versions = require("tests/gen").versions
local buttons = require("tests/gen").buttons
local BASE_TIMESTAMP = require("tests/gen").BASE_TIMESTAMP

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
