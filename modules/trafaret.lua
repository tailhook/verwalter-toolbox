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
local _Bool = {}
local _Choice = {}
local _Enum = {}

function _Atom:convert(value, validator, path)
    if value == self.value then
        return value
    end
    validator:add_error(path, self,
        "Value must be", self.value, ", but is", value)
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

function _Bool:convert(value, validator, path)
    if type(value) == 'boolean' then
        return value
    end
    validator:add_error(path, self,
        "Value is not a boolean, but", type(value))
    return not not value
end

local function Bool(_)
    local obj = {}
    setmetatable(obj, {__index=_Bool})
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
        if keyobj then
            result[key] = keyobj.trafaret:convert(item, validator, keypath)
        elseif not self.allow_extra then
            validator:add_error(keypath, self, "Unexpected key")
        else
            result[key] = item
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
            if not key.optional then
                table.insert(required_keys, key.key)
            end
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

function _Choice:convert(value, validator, path)
    local choice_value = value[self.key]
    if choice_value == nil then
        validator:add_error(path, self,
            "Dict must contain", self.key)
        return value
    end
    local cur_t = self.options[choice_value]
    if cur_t == nil then
        validator:add_error(path, self,
            "Key", self.key, "must be one of",
            table.concat(func.keys(self.options), ", "))
        return value
    end
    return cur_t:convert(value, validator, path.."<choice "..choice_value..">")
end

local function Choice(params)
    local key = params[1]
    params[1] = nil
    local obj = {key=key, options=params}
    setmetatable(obj, {__index=_Choice})
    return obj
end

function _Enum:convert(value, validator, path)
    for _, item in pairs(self.options) do
        if value == item then
            return value
        end
    end
    validator:add_error(path, self,
        "Must be one of", table.concat(self.options, ", "))
    return nil
end

local function Enum(params)
    local arr = {}
    for i, item in ipairs(params) do
        arr[i] = item
    end
    local obj = {options=arr}
    setmetatable(obj, {__index=_Enum})
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
    Enum=Enum,
    Choice=Choice,
    Bool=Bool,
    validate=validate,
}
