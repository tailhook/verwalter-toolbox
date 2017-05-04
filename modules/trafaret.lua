local package = (...):match("(.-)[^/]+$")
local func = require(package.."func")

local _Validator = {}
local _Number = {}
local _String = {}
local _Dict = {}
local _Key = {}
local _List = {}
local _Map = {}
local _Atom = {}
local _Or = {}

function _Atom:convert(value, validator, path)
    if value == self.value then
        return value
    end
    validator:add_error(path, self,
        "Value must be ", self.value, ", but is ", value)
    return self.value
end

local function Atom(props)
    local obj = {value=props[1]}
    setmetatable(obj, {__index=_Atom})
    return obj
end

function _Number:convert(value, validator, path)
    if type(value) == 'number' then
        return value
    end
    validator:add_error(path, self,
        "Value is not a number, but", type(value))
    return tonumber(value)
end

local function Number(_)
    local obj = {}
    setmetatable(obj, {__index=_Number})
    return obj
end

function _String:convert(value, validator, path)
    if type(value) ~= 'string' then
        validator:add_error(path, self,
            "Value is not a string, but", type(value))
        return tostring(value)
    end
    if self.pattern ~= nil then
        if not string.find(value, self.pattern) then
            validator:add_error(path, self,
                "Value doesn't match pattern ", self.pattern)
        end
    end
    return value
end

local function String(props)
    local obj = {
        pattern=props.pattern,
    }
    setmetatable(obj, {__index=_String})
    return obj
end

local function Key(props)
    local key = props[1]
    local obj = {
        key=key,
        optional=not not props.optional,
        default=props.default,
    }
    setmetatable(obj, {__index=_Key})
    return obj
end

function _Key:with_trafaret(trafaret)
    local obj = {
        key=self.key,
        optional=self.optional,
        default=self.default,
        trafaret=trafaret,
    }
    setmetatable(obj, {__index=_Key})
    return obj
end

function _Dict:convert(value, validator, path)
    if type(value) ~= 'table' then
        validator:add_error(path, self,
            "Value is not a table, but", type(value))
        return {}
    end
    local result = {}
    for key, item in pairs(value) do
        local keypath = path..'.'..key
        local keyobj = self.all_keys[key]
        if not keyobj and not self.allow_extra then
            validator:add_error(keypath, self, "Unexpected key")
        else
            result[key] = keyobj.trafaret:convert(item, validator, keypath)
        end
    end
    for _, key in pairs(self.required_keys) do
        if result[key] == nil then
            local default = self.all_keys[key].default
            if default ~= nil then
                result[key] = default
            else
                local keypath = path..'.'..key
                validator:add_error(keypath, self, "Required key")
            end
        end
    end
    return result
end

local function Dict(keys)
    local allow_extra = false
    local all_keys = {}
    local required_keys = {}
    for key, value in pairs(keys) do
        if key == "allow_extra" then
            allow_extra = not not value
        else
            if type(key) == 'string' then
                key = Key { key }:with_trafaret(value)
            else
                key = key:with_trafaret(value)
            end
            all_keys[key.key] = key
            table.insert(required_keys, key.key)
        end
    end
    local obj = {
        all_keys=all_keys,
        required_keys=required_keys,
        allow_extra=allow_extra,
    }
    setmetatable(obj, {__index=_Dict})
    return obj
end

function _Map:convert(value, validator, path)
    if type(value) ~= 'table' then
        validator:add_error(path, self,
            "Value is not a table, but", type(value))
        return {}
    end
    local result = {}
    for k, v in pairs(value) do
        local nk = self.key:convert(k, validator, path .. "<key>")
        local nv = self.value:convert(v, validator, path .. "." .. nk)
        result[nk] = nv
    end
    return result
end

local function Map(props)
    local key = props[1]
    local value = props[2]
    local obj = {
        key=key,
        value=value,
    }
    setmetatable(obj, {__index=_Map})
    return obj
end

local function Validator()
    local validator = {
        errors={}
    }
    setmetatable(validator, {__index=_Validator})
    return validator
end

function _Validator:add_error(path, _, message, ...)
    local text = path .. ": " .. message
    for _, v in pairs({...}) do
        text = text .. " " .. tostring(v)
    end
    table.insert(self.errors, text)
end

local function List(props)
    local item = props[1]
    local obj = {
        item=item,
    }
    setmetatable(obj, {__index=_List})
    return obj
end

function _List:convert(value, validator, path)
    if type(value) ~= 'table' then
        validator:add_error(path, self,
            "Value is not a table, but", type(value))
        return {}
    end
    local result = {}
    for i, item in ipairs(value) do
        result[i] = self.item:convert(item, validator, path .. '.' .. i)
    end
    return result
end

function _Or:convert(value, validator, path)
    local real_value = value
    local all_errors = {}
    for i, val in ipairs(self.options) do
        local cur_val = Validator()
        local cur = val:convert(value, cur_val,
            path .. '.<alternative ' .. i .. '>')
        if #cur_val.errors == 0 then
            return cur
        end
        func.array_extend(all_errors, cur_val.errors)
    end
    func.array_extend(validator.errors, all_errors)
    return real_value
end

local function Or(params)
    local arr = {}
    for i, item in ipairs(params) do
        arr[i] = item
    end
    local obj = {options=arr}
    setmetatable(obj, {__index=_Or})
    return obj
end

local function validate(trafaret, value)
    local val = Validator()
    local status, cleaned = xpcall(
        function() return trafaret:convert(value, val, '') end,
        debug.traceback)
    if not status then
        table.insert(val.errors, cleaned)
        cleaned = value  -- keep original value
    end
    if #val.errors == 0 then
        return true, cleaned
    else
        return false, cleaned, val.errors
    end
end

return {
    Atom=Atom,
    Number=Number,
    String=String,
    Dict=Dict,
    Key=Key,
    List=List,
    Map=Map,
    Or=Or,
    validate=validate,
}
