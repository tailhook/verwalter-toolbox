local repr = require("modules/repr")

local _MockLogger = {}

local function Logger(role, prefix, list)
    local obj = {
        role_name=role or 'no-role',
        prefix=prefix or '',
        list=list or {},
    }
    setmetatable(obj, {__index=_MockLogger})
    return obj
end

function _MockLogger:sub(name)
    if self.prefix == '' then
        return Logger(self.role_name, ' '..name..':')
    else
        return Logger(self.role_name,
            self.prefix.sub(1, -1)..'.'..name..':')
    end
end

local function log(...)
    local text = ''
    for i, v in ipairs({...}) do
        if i > 1 then
            text = text .. " "
        end
        if type(v) == 'table' then
            text = text .. repr.log_repr(v)
        else
            text = text .. tostring(v)
        end
    end
    print(text)
    return text
end

function _MockLogger:debug(...)
    table.insert(self.list, log(self.role_name, "DEBUG", ...))
end


function _MockLogger:error(...)
    table.insert(self.list, log(self.role_name, "ERROR", ...))
end

function _MockLogger:change(...)
    table.insert(self.list, log(self.role_name, 'CHANGE', ...))
end

function _MockLogger:invalid(msg, data, err)
    log(self.role_name, 'ERROR', tostring(msg)..", data:", repr.log_repr(data))
    for _, e in ipairs(err) do
        log(self.role_name, 'ERROR', tostring(msg)..", error:", e)
    end
end

return {
    Logger=Logger,
}
