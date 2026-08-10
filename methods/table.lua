local methods = {}

local function isBuffer(value)
    return type(value) == "buffer" or typeof(value) == "buffer"
end

local function tableToString(data, root, indents, seen)
    local dataType = type(data)
    local valueType = typeof(data)

    if dataType == "userdata" or valueType ~= dataType or isBuffer(data) then
        return (valueType == "Instance" and getInstancePath(data)) or userdataValue(data)
    elseif dataType == "string" then
        if #(data:gsub("%w", ""):gsub("%s", ""):gsub("%p", "")) > 0 then
            local success, result = pcall(toUnicode, data)
            return (success and result) or toString(data)
        end

        return dataToString(data)
    elseif dataType == "table" then
        indents = indents or 1
        seen = seen or {}

        if seen[data] then
            return "OH_CYCLIC_PROTECTION"
        end

        seen[data] = true
        local parts = { "{\n" }
        local elements = 0
        local indent = ("\t"):rep(indents)

        for index, value in pairs(data) do
            if index == root or value == root then
                parts[#parts + 1] = ("%sOH_CYCLIC_PROTECTION,\n"):format(indent)
            else
                parts[#parts + 1] = ("%s[%s] = %s,\n"):format(
                    indent,
                    tableToString(index, root or data, indents + 1, seen),
                    tableToString(value, root or data, indents + 1, seen)
                )
            end

            elements = elements + 1
        end

        seen[data] = nil

        if elements > 0 then
            parts[#parts] = parts[#parts]:sub(1, -3)
            parts[#parts + 1] = "\n" .. ("\t"):rep(indents - 1) .. "}"
            return table.concat(parts)
        end

        return "{}"
    end

    return tostring(data)
end

local function compareTables(x, y)
    for index, value in pairs(x) do
        if value ~= y[index] then
            return false
        end
    end

    for index in pairs(y) do
        if x[index] == nil then
            return false
        end
    end

    return true
end

methods.tableToString = tableToString
methods.compareTables = compareTables
return methods
