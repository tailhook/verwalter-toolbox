local LOG_REPR_MAX_KEYS = 10
local LOG_REPR_MAX_LEVEL = 2
local LOG_REPR_MAX_STR = 100

local function log_repr(obj, _level)
    local typ = type(obj)
    local level = _level or 0
    if level > LOG_REPR_MAX_LEVEL then
        return "..."
    end
    if typ == 'table' then
        local result = '{'
        local keys = 0
        for k, v in pairs(obj) do
            keys = keys + 1
            if keys > LOG_REPR_MAX_KEYS then
                result = result .. ', ...'
                break
            end
            if result ~= '{' then
                result = result .. ", "
            end
            if type(k) == "number" then
                result = result .. log_repr(v, level)
            elseif k:match("^%w") then
                result = result .. k .. "=" .. log_repr(v, level+1)
            end
        end
        result = result .. "}"
        return result
    elseif typ == 'string' then
        local data = obj
        if obj:len() > LOG_REPR_MAX_STR then
            data = obj.substr(0, 25)
        end
        -- TODO(tailhook) better escaping
        return '"'..
            data:gsub("\n", "\\n"):gsub("\r", "\r"):gsub('"', '\\"')
            ..'"'
    else
        return tostring(obj)
    end
end

return {
    log_repr=log_repr,
}
