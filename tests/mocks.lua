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
        return Logger(self.role_name, name, self.list)
    else
        return Logger(self.role_name, self.prefix .. '.' .. name, self.list)
    end
end

local function log(...)
    local text = ''
    for i, v in ipairs({...}) do
        if i > 1 then
            text = text .. " "
        end
        text = text .. tostring(v)
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
    -- TODO(tailhook) print repr of data
    for _, e in ipairs(err) do
        log(self.role_name, 'ERROR', msg, data, e)
    end
end

return {
    Logger=Logger,
}
