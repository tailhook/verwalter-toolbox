local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local log = require("modules/log")
local mocks = require("tests/mocks")

describe("log: wrap scheduler", function()
    test("normal_output", function()
        local data, output = log.wrap_scheduler(function()
            return {a=1}
        end)({})
        assert.is.same(data, '{"a":1}')
        assert.is.same(output, "")
    end)
    test("print", function()
        local data, output = log.wrap_scheduler(function()
            print("hello")
            return {a=1}
        end)({})
        assert.is.same(data, '{"a":1}')
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
            return {a=1}
        end)({})
        assert.is.same(data, nil)
        assert(output:find("attempt to call a nil value"))
        assert(output:find("in local 'test_subfunction'"))
    end)
    test("role error", function()
        local data, output = log.wrap_scheduler(function()
            log.role_error("me", "hello")
            return {a=1}
        end)({})
        assert.is.same(data, '{"a":1}')
        assert.is.same(output,
            "[me]:ERROR: hello\n")
    end)
    test("role debug", function()
        local data, output = log.wrap_scheduler(function()
            log.role_debug("other", "some", "data")
            return {a=1}
        end)({})
        assert.is.same(data, '{"a":1}')
        assert.is.same(output,
            "[other]:DEBUG: some data\n")
    end)
    test("role change", function()
        local data, output = log.wrap_scheduler(function()
            log.role_change("other", "important", "change")
            return {a=1}
        end)({})
        assert.is.same('{"a":1,"changes":["other: important change"]}', data)
        assert.is.same(output,
            "[other]:CHANGE: important change\n")
    end)

    test("logger debug", function()
        local logger = log.Logger("other")
        local data, output = log.wrap_scheduler(function()
            logger:debug("some", "data")
            return {a=1}
        end)({})
        assert.is.same(data, '{"a":1}')
        assert.is.same(output,
            "[other]:DEBUG: some data\n")
    end)

    test("table value", function()
        local data, output = log.wrap_scheduler(function()
            log.role_debug("other", "data:", {hello=1})
            return {a=1}
        end)({})
        assert.is.same(data, '{"a":1}')
        assert.is.same(output,
            "[other]:DEBUG: data: {hello=1}\n")
    end)
end)

describe("log: test_mocks", function()
    test("logger debug", function()
        local logger = mocks.Logger("other")
        logger:debug("some", "data")
        assert.is.same(logger.list,
            {"other DEBUG some data"})
    end)
end)
