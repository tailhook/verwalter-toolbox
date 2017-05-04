local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local T = require("modules/trafaret")

describe("trafaret: atom", function()
    local number = T.Atom{1}
    local str = T.Atom{"x"}
    test("validate number", function()
        assert(T.validate(number, 1))
    end)
    test("validate wrong number", function()
        assert(not T.validate(number, 2))
        assert(not T.validate(number, '1'))
    end)
    test("validate string", function()
        assert(T.validate(str, 'x'))
    end)
    test("validate wrong string", function()
        assert(not T.validate(str, 2))
        assert(not T.validate(str, 'xx'))
        assert(not T.validate(str, 'y'))
    end)
end)

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

describe("trafaret: string", function()
    local str = T.String{}
    local ver = T.String{pattern="^v%d"}
    test("validate str", function()
        assert(T.validate(str, "xxx"))
        assert(T.validate(str, "111"))
    end)
    test("validate number", function()
        local res, val, err = T.validate(str, 123)
        assert(not res)
        assert.is.same(val, "123")
        assert.is.same(err, {": Value is not a string, but number"})
    end)
    test("validate table", function()
        local res, _, err = T.validate(str, {})
        assert(not res)
        assert.is.same(err, {": Value is not a string, but table"})
    end)
    test("validate ver", function()
        assert(T.validate(ver, "v1"))
        assert(T.validate(ver, "v1.2.3"))
        assert(T.validate(ver, "v1.2.3"))
        assert(not T.validate(ver, "1.2.3"))
        assert(not T.validate(ver, "xxx"))
        assert(not T.validate(ver, "vvv"))
    end)
end)

describe("trafaret: string", function()
    local str = T.String{}
    test("validate str", function()
        assert(T.validate(str, "xxx"))
        assert(T.validate(str, "111"))
    end)
    test("validate number", function()
        local res, val, err = T.validate(str, 123)
        assert(not res)
        assert.is.same(val, "123")
        assert.is.same(err, {": Value is not a string, but number"})
    end)
    test("validate table", function()
        local res, _, err = T.validate(str, {})
        assert(not res)
        assert.is.same(err, {": Value is not a string, but table"})
    end)
end)

describe("trafaret: dict", function()
    local fixed = T.Dict {
        [T.Key{"xxx"}] = T.Number{},
        [T.Key{"yyy"}] = T.Number{},
    }
    --[[
    local extra = T.Dict {
        [T.Key{"xxx"}] = T.Number{},
        [T.Key{"yyy"}] = T.Number{},
        allow_extra=true,
    }
    local opt = T.Dict {
        [T.Key{"xxx", optional=true}] = T.Number{},
        [T.Key{"yyy"}] = T.Number{},
    }
    ]]--
    test("fixed ok", function()
        local res, val, _ = T.validate(fixed, {xxx=1, yyy=2})
        assert(res)
        assert.is.same(val, {yyy=2, xxx=1})
    end)
    test("fixed missing", function()
        local res, _, _ = T.validate(fixed, {xxx=1})
        assert(not res)
    end)
    test("fixed extra", function()
        local res, _, _ = T.validate(fixed, {xxx=1, yyy=3, zzz=4})
        assert(not res)
    end)
    test("fixed wrong type", function()
        local res, _, _ = T.validate(fixed, {xxx="1", yyy=2})
        assert(not res)
    end)
end)

describe("trafaret: list", function()
    local lst = T.List { T.Number{} }
    test("empty", function()
        local res, val, _ = T.validate(lst, {})
        assert(res)
        assert.is.same(val, {})
    end)
    test("normal", function()
        local res, val, _ = T.validate(lst, {1, 2, 3})
        assert(res)
        assert.is.same(val, {1, 2, 3})
    end)
    test("bad", function()
        local res, val, _ = T.validate(lst, {1, "2", 3})
        assert(not res)
        assert.is.same(val, {1, 2, 3})
    end)
end)

describe("trafaret: map", function()
    local map = T.Map { T.String{}, T.Number{} }
    test("empty", function()
        local res, val, _ = T.validate(map, {})
        assert(res)
        assert.is.same(val, {})
    end)
    test("normal", function()
        local res, val, _ = T.validate(map, {a=1, b=2})
        assert(res)
        assert.is.same(val, {a=1, b=2})
    end)
    test("bad", function()
        local res, val, _ = T.validate(map, {a="1", b="b", c=3})
        assert(not res)
        assert.is.same(val, {a=1, c=3})  --- b=nil skipped
    end)
end)
