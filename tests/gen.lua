local func = require("modules/func")

local function schedule(table)
    table = func.copy(table)
    if table.actions then
        table.actions = func.map_to_dict(function(key, value)
            if key < 1000000000000 then
                -- just some arbitrary base time
                return 1465479290000 + key*7, value
            else
                return key, value
            end
        end, table.actions)
    end
    return table
end

local function button(btn)
    return {button=btn}
end

return {
    schedule=schedule,
    button=button,
}
