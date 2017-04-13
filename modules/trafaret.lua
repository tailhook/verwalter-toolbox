local _Validator = {}
local _Number = {}


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
    Number=Number,
    validate=validate,
}
