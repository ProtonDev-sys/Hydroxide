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

local function toString(value)
    local valueType = typeof(value)
    local rawType = type(value)

    if rawType == "table" or valueType == "table" then
        local metatable = getMetatable and getMetatable(value)
        local tostringHandler = metatable and rawget(metatable, "__tostring")

        if not metatable or not tostringHandler then
            return tostring(value)
        end

        rawset(metatable, "__tostring", nil)

        local stringValue = tostring(value):gsub((valueType == "userdata" and "userdata: ") or "table: ", "")

        rawset(metatable, "__tostring", tostringHandler)

        return stringValue
    elseif isBuffer(value, valueType) then
        return "buffer"
    elseif rawType == "function" then
        local closureName = getInfo(value).name or ""
        return (closureName == "" and "Unnamed function") or closureName
    elseif rawType == "userdata" or valueType ~= rawType then
        return userdataValue(value)
    end

    return tostring(value)
end

local function toUnicode(value)
    local codepoints = "utf8.char("

    for _, codepoint in utf8.codes(value) do
        codepoints = codepoints .. codepoint .. ", "
    end

    return codepoints:sub(1, -3) .. ")"
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

methods.toString = toString
methods.dataToString = dataToString
methods.toUnicode = toUnicode
return methods
