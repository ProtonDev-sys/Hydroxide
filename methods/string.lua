local methods = {}

local escapeCharacters = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\0"] = "\\0",
    ["\n"] = "\\n",
    ["\t"] = "\\t",
    ["\f"] = "\\f",
    ["\r"] = "\\r",
    ["\v"] = "\\v",
    ["\a"] = "\\a",
    ["\b"] = "\\b"
}

local function escapeString(value)
    return value:gsub("[%c%z\\\"]", escapeCharacters)
end

local function isBuffer(value, valueType)
    return type(value) == "buffer" or valueType == "buffer"
end

local function truncate(value, maxLength)
    if #value <= maxLength then
        return value
    end

    return value:sub(1, math.max(1, maxLength - 3)) .. "..."
end

local function toString(value)
    local valueType = typeof(value)
    local rawType = type(value)

    if rawType == "table" or valueType == "table" then
        return tostring(value)
    elseif isBuffer(value, valueType) then
        return "buffer"
    elseif rawType == "function" then
        local ran, info = pcall(getInfo, value, "n")
        local closureName = ran and info and info.name or ""
        return (closureName == "" and "Unnamed function") or closureName
    elseif rawType == "userdata" or valueType ~= rawType then
        return userdataValue(value)
    end

    return tostring(value)
end

local function toUnicode(value)
    local codepoints = {}

    for _, codepoint in utf8.codes(value) do
        codepoints[#codepoints + 1] = tostring(codepoint)
    end

    return "utf8.char(" .. table.concat(codepoints, ", ") .. ")"
end

local function dataToString(data)
    local rawType = type(data)
    local valueType = typeof(data)

    if rawType == "string" then
        return '"' .. escapeString(data) .. '"'
    elseif rawType == "table" or valueType == "table" then
        return tableToString(data)
    elseif isBuffer(data, valueType) then
        return userdataValue(data)
    elseif rawType == "userdata" or valueType ~= rawType then
        if valueType == "Instance" then
            return getInstancePath(data)
        end

        return userdataValue(data)
    elseif rawType == "boolean" or rawType == "number" or rawType == "nil" then
        return tostring(data)
    end

    return toString(data)
end

local function summarizeValue(value, maxLength)
    local settings = oh and oh.Settings or {}
    local limit = tonumber(maxLength) or settings.MaxArgumentPreviewLength or 240
    local rawType = type(value)
    local valueType = typeof(value)
    local summary

    limit = math.max(40, math.floor(limit))

    if rawType == "string" then
        summary = '"' .. escapeString(truncate(value, limit - 2)) .. '"'
    elseif rawType == "table" or valueType == "table" then
        local count = 0
        local capped = false
        local counted = pcall(function()
            for _ in next, value do
                count = count + 1

                if count >= 100 then
                    capped = true
                    break
                end
            end
        end)

        summary = counted and ("table (%d%s entries)"):format(count, capped and "+" or "") or "table"
    elseif valueType == "Instance" then
        local described, description = pcall(function()
            return ("%s %s"):format(value.ClassName, value.Name)
        end)

        summary = described and description or "Instance"
    elseif isBuffer(value, valueType) then
        local measured, size = pcall(function()
            return buffer.len(value)
        end)

        summary = measured and ("buffer (%d bytes)"):format(size) or "buffer"
    elseif rawType == "function" then
        local described, description = pcall(toString, value)
        summary = described and ("function %s"):format(description) or "function"
    elseif rawType == "nil" or rawType == "boolean" or rawType == "number" then
        summary = tostring(value)
    else
        local described, description = pcall(toString, value)
        summary = described and description or valueType
    end

    return truncate(tostring(summary), limit)
end

methods.toString = toString
methods.dataToString = dataToString
methods.summarizeValue = summarizeValue
methods.toUnicode = toUnicode
return methods
