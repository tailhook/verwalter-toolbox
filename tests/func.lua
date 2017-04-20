local assert = require('luassert')
local busted = require('busted')
local test = busted.test
local describe = busted.describe

local func = require("modules/func")

describe("map: only maps indexed part", function()
    local mapfunc = function(a) return a.."1" end
    test("map list", function()
        assert.are.same(
            func.map(mapfunc, {"x", "y", "z"}),
            {"x1", "y1", "z1"})
    end)

    -- Map totaly skips non-indexed part of a table
    test("map dict", function()
        assert.are.same(
            func.map(mapfunc, {"x", b="y", c="z"}),
            {"x1"})
    end)
end)

describe("map_pairs: maps key value pairs, preserving keys", function()
    local mapfunc = function(k, v) return k .. ": " .. v end
    test("(list)", function()
        assert.are.same(
            func.map_pairs(mapfunc, {"x", "y", "z"}),
            {"1: x", "2: y", "3: z"})
    end)
    test("(dict)", function()
        assert.are.same(
            func.map_pairs(mapfunc, {"x", b="y", c="z"}),
            {"1: x", b="b: y", c="c: z"})
    end)
end)

describe("map_reverse: map indexed part but in reverse order", function()
    local mapfunc = function(a) return a.."1" end
    test("map list", function()
        assert.are.same(
            func.map_reverse(mapfunc, {"x", "y", "z"}),
            {"z1", "y1", "x1"})
    end)

    -- Map totaly skips non-indexed part of a table
    test("map dict", function()
        assert.are.same(
            func.map_reverse(mapfunc, {"x", "y", b="z", c="w"}),
            {"y1", "x1"})
    end)
end)


describe("map_to_dict: like map_pairs but key is returned", function()
    local mapfunc = function(k, v) return v, k end
    test("(list)", function()
        assert.are.same({x=1, y=2, z=3},
            func.map_to_dict(mapfunc, {"x", "y", "z"}))
    end)
    test("(dict)", function()
        assert.are.same({x=1, y="b", z="c"},
            func.map_to_dict(mapfunc, {"x", b="y", c="z"}))
    end)
end)

describe("map_to_array: maps key-value pairs and returns list", function()
    local mapfunc = function(k, v) return k .. ": " .. v end
    test("(list)", function()
        assert.are.same({"1: x", "2: y", "3: z"},
            func.map_to_array(mapfunc, {"x", "y", "z"}))
    end)

    test("(dict)", function()
        assert.are.same({"1: x", "b: y", "c: z"},
            func.sorted(func.map_to_array(mapfunc, {"x", b="y", c="z"})))
    end)
end)

describe("filter: filter values", function()
    local filter = function(val) return val ~= 'y' end
    test("(list)", function()
        assert.are.same({"x", "z"},
            func.filter(filter, {"x", "y", "z"}))
    end)

    -- return value is always a list
    test("(dict)", function()
        assert.are.same({"x", "z"},
            func.sorted(func.filter(filter, {"x", b="y", c="z"})))
    end)
end)

describe("filter_pairs: filter key values to key values", function()
    local filter = function(k, v) if v ~= 'y' then return v, k end end
    test("(list)", function()
        assert.are.same({x=1, z=3},
            func.filter_pairs(filter, {"x", "y", "z"}))
    end)

    -- return value is always a list
    test("(dict)", function()
        assert.are.same({x=1, z="c"},
            func.sorted(func.filter_pairs(filter, {"x", b="y", c="z"})))
    end)
end)

describe("count_keys: count keys in a table", function()
    -- list case is useless in practice, but we test
    test("(list)", function()
        assert.are.same(3,
            func.count_keys({"x", "y", "z"}))
    end)
    test("(dict)", function()
        assert.are.same(3,
            func.count_keys({"x", b="y", c="z"}))
    end)
end)

describe("copy: a deep copy of table", function()
    test("(dict)", function()
        assert.are.same({"x", y={"z"}},
            func.copy({"x", y={"z"}}))
    end)
    test("(mutate)", function()
        local x = {"x", y={"z"}}
        local y = func.deepcopy(x)
        table.insert(y.y, "zz")
        assert.are.same(x, {"x", y={"z"}})
        assert.are.same(y, {"x", y={"z", "zz"}})
    end)
end)
describe("copy: a shallow copy of table", function()
    test("(list)", function()
        assert.are.same({"x", "y", "z"},
            func.copy({"x", "y", "z"}))
    end)
    test("(dict)", function()
        assert.are.same({"x", b="y", c="z"},
            func.copy({"x", b="y", c="z"}))
    end)
    test("(number)", function()
        assert.are.same(7, func.copy(7))
    end)
    test("(string)", function()
        assert.are.same("xyz", func.copy("xyz"))
    end)
    test("(boolean)", function()
        assert.are.same(true, func.copy(true))
        assert.are.same(false, func.copy(false))
    end)
    test("(nil)", function()
        assert.are.same(nil, func.copy(nil))
    end)
end)

describe("contains: key in a table", function()
    test("(list)", function()
        assert.are.same(true, func.contains({"x", "y", "z"}, "x"))
        assert.are.same(true, func.contains({"x", "y", "z"}, "y"))
        assert.are.same(false, func.contains({"x", "y", "z"}, "a"))
        assert.are.same(false, func.contains({"x", "y", "z"}, 1))
    end)
    test("(dict)", function()
        assert.are.same(true, func.contains({"x", b="y", c="z"}, "x"))
        assert.are.same(true, func.contains({"x", b="y", c="z"}, "y"))
        assert.are.same(false, func.contains({"x", b="y", c="z"}, "a"))
        assert.are.same(false, func.contains({"x", b="y", c="z"}, 1))
    end)
end)

describe("sorted: return a sorted copy of a table", function()
    test("(list)", function()
        assert.are.same({"x", "y", "z"}, func.sorted({"z", "y", "x"}))
        assert.are.same({"x", "y", "z"}, func.sorted({"x", "z", "y"}))
    end)
    test("(dict)", function()
        assert.are.same({c="x", b="y", a="z"},
            func.sorted({a="z", b="y", c="x"}))
        assert.are.same({a="x", c="y", b="z"},
            func.sorted({a="x", b="z", c="y"}))
    end)
end)

describe("range_step_num", function()
    test("(positive)", function()
        assert.are.same({2, 4, 6}, func.range_step_num(2, 2, 3))
    end)
    test("(negative)", function()
        assert.are.same({6, 4, 2}, func.range_step_num(6, -2, 3))
    end)
end)

describe("repeat_num", function()
    test("(int)", function()
        assert.are.same({2, 2}, func.repeat_num(2, 2))
        assert.are.same({7, 7, 7, 7}, func.repeat_num(7, 4))
    end)

    test("(str)", function()
        assert.are.same({"x", "x", "x"}, func.repeat_num("x", 3))
    end)

    test("zero times", function()
        assert.are.same({}, func.repeat_num("x", 0))
    end)
end)

describe("list_to_set", function()

    test("(list)", function()
        assert.are.same({x=true, y=true}, func.list_to_set({"x", "y"}))
    end)

    test("(dict)", function()
        assert.are.same({x=true, y=true}, func.list_to_set({a="x", b="y"}))
    end)

end)

describe("merge_tables", function()
    test("empty", function()
        assert.are.same({}, func.merge_tables())
    end)
    test("single", function()
        assert.are.same({x=1, y=2}, func.merge_tables({x=1, y=2}))
    end)
    test("two", function()
        assert.are.same({x=1, y=2, c=3}, func.merge_tables({x=1}, {y=2, c=3}))
    end)
    test("dict with list", function()
        assert.are.same({7, 8, x=1, y=2},
            func.merge_tables({x=1}, {y=2}, {7, 8}))
    end)
end)

describe("array_extend", function()
    test("empty", function()
        assert.are.same({}, func.array_extend({}))
    end)
    test("single", function()
        assert.are.same({1, 2}, func.array_extend({}, {1, 2}))
        assert.are.same({1, 2, 3, 4}, func.array_extend({1, 2}, {3, 4}))
    end)
    test("two", function()
        assert.are.same({3, 1, 2}, func.array_extend({}, {3}, {1, 2}))
    end)
end)

describe("sum: sum numerical values of the dict or list", function()
    test("(list)", function()
        assert.are.same(
            func.sum({1, 2, 3}),
            6)
    end)
    test("(dict)", function()
        assert.are.same(
            func.sum({7, b=8, c=9}),
            24)
    end)
end)
