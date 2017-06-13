local package = (...):match("(.-)[^/]+$")
local json = require(package.."json")
local func = require(package.."func")
local repr = require(package.."repr")

local text = nil
local changes = {}
local _Logger = {}

local function log(role_name, level_name, ...)
    if text == nil then  -- in unit tests probably
        print(role_name, level_name, ...)
        return
    end
    text = text .. "["..role_name.."]:"..level_name..": "
    for i, v in pairs({...}) do
        if i > 1 then
            text = text .. " "
        end
        if type(v) == 'table' then
            text = text .. repr.log_repr(v)
        else
            text = text .. tostring(v)
        end
    end
    text = text .. "\n"
end

local function print(...)
    log("no-role", "DEBUG", ...)
end

local function role_error(role_name, ...)
    log(role_name, "ERROR", ...)
end

local function role_debug(role_name, ...)
    log(role_name, "DEBUG", ...)
end

local function role_change(role_name, ...)
    log(role_name, "CHANGE", ...)
    local change = role_name .. ":"
    for _, v in pairs({...}) do
        change = change .. " "
        if type(v) == 'table' then
            change = change .. repr.log_repr(v)
        else
            change = change .. tostring(v)
        end
    end
    table.insert(changes, change)
end

local function wrap_scheduler(real_scheduler)
    return function(state)
        local original_print = _G.print
        text = ""
        changes = {}
        _G.print = print

        local flag, value = xpcall(
            function()
                local data = real_scheduler(state)
                if #changes ~= 0 then
                    if not data.changes then
                        data.changes = {}
                    end
                    func.array_extend(data.changes, changes)
                end
                return json:encode(data)
            end,
            debug.traceback)

        local current_text = text
        _G.print = original_print
        text = nil
        changes = nil

        if flag then
            return value, current_text
        else
            return nil, current_text .. string.format("\nError: %s", value)
        end
    end
end

local function Logger(role, prefix)
    local obj = {
        role_name=role or 'no-role',
        prefix=prefix or '',
    }
    setmetatable(obj, {__index=_Logger})
    return obj
end

function _Logger:sub(name)
    if self.prefix == '' then
        return Logger(self.role_name, name)
    else
        return Logger(self.role_name, self.prefix .. '.' .. name)
    end
end

function _Logger:debug(...)
    log(self.role_name, "DEBUG", self.prefix .. ':', ...)
end

function _Logger:error(...)
    log(self.role_name, "ERROR", self.prefix .. ':', ...)
end

function _Logger:change(...)
    role_change(self.role_name, self.prefix .. ':', ...)
end

function _Logger:invalid(msg, data, err)
    log(self.role_name, 'ERROR', self.prefix .. ':',
        tostring(msg)..", data:", data)
    for _, e in ipairs(err) do
        log(self.role_name, 'ERROR', self.prefix .. ':',
            tostring(msg)..", error:", e)
    end
end

return {
    wrap_scheduler=wrap_scheduler,
    role_error=role_error,
    role_debug=role_debug,
    role_change=role_change,
    Logger=Logger,
}
