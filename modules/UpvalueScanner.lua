local UpvalueScanner = {}
local Closure = import("objects/Closure")
local Upvalue = import("objects/Upvalue")
local checkpoint = import("modules/Scanner").checkpoint

local requiredMethods = {
    ["getLuaClosures"] = true,
    ["getInfo"] = true,
    ["getUpvalue"] = true,
    ["setUpvalue"] = true,
    ["getUpvalues"] = true
}

local function getClosureName(closure)
    local ran, info = pcall(getInfo, closure, "n")
    local name = ran and type(info) == "table" and info.name
    return type(name) == "string" and name or ""
end

local function compareUpvalue(query, loweredQuery, upvalue, ignoreNumberMatch)
    local upvalueType = type(upvalue)

    if upvalueType == "string" then
        local loweredValue = upvalue:lower()
        return query == upvalue or loweredValue:find(loweredQuery, 1, true) ~= nil
    elseif upvalueType == "number" and not ignoreNumberMatch then
        local numericQuery = tonumber(query)
        return numericQuery == upvalue or ("%.2f"):format(upvalue) == query
    elseif upvalueType == "boolean" then
        return tostring(upvalue) == loweredQuery
    elseif upvalueType == "userdata" then
        local ran, matches = pcall(function()
            if typeof(upvalue) == "Instance" then
                local name = upvalue.Name
                return name == query or name:lower():find(loweredQuery, 1, true) ~= nil
            end
            return toString(upvalue) == query
        end)
        return ran and matches
    elseif upvalueType == "function" then
        local closureName = getClosureName(upvalue)
        local loweredName = closureName:lower()

        return query == closureName or loweredName:find(loweredQuery, 1, true) ~= nil
    end

    return false
end

local function scan(query, deepSearch, options)
    local upvalues = {}
    query = tostring(query or "")
    local loweredQuery = query:lower()
    local cancelled = checkpoint(options)
    if cancelled(true) then
        return upvalues, true
    end
    local closures = getLuaClosures()
    assert(type(closures) == "table", "getLuaClosures did not return a table")
    if cancelled(true) then
        return upvalues, true
    end
    local seen = {}

    for _, closure in next, closures do
        if cancelled() then
            return upvalues, true
        end
        local ran, closureUpvalues = false, nil
        if type(closure) == "function" and not seen[closure] then
            seen[closure] = true
            ran, closureUpvalues = pcall(getUpvalues, closure)
        end
        if cancelled(true) then
            return upvalues, true
        end

        if ran and type(closureUpvalues) == "table" then
            for index, value in next, closureUpvalues do
                if cancelled() then
                    return upvalues, true
                end
                local valueType = type(value)

                if valueType ~= "table" and compareUpvalue(query, loweredQuery, value) then
                    local storage = upvalues[closure]

                    if not storage then
                        storage = Closure.new(closure)
                        storage.Upvalues = {}
                        storage.TemporaryUpvalues = {}
                        upvalues[closure] = storage
                    end

                    storage.Upvalues[index] = Upvalue.new(storage, index, value)
                elseif deepSearch and valueType == "table" then
                    local storage = upvalues[closure]
                    local tableUpvalue

                    for key, nestedValue in next, value do
                        if cancelled() then
                            return upvalues, true
                        end
                        if (key ~= value and nestedValue ~= value)
                            and (
                                compareUpvalue(query, loweredQuery, key, true)
                                or compareUpvalue(query, loweredQuery, nestedValue)
                            )
                        then
                            if not storage then
                                storage = Closure.new(closure)
                                storage.Upvalues = {}
                                storage.TemporaryUpvalues = {}
                                upvalues[closure] = storage
                            end

                            if not tableUpvalue then
                                tableUpvalue = Upvalue.new(storage, index, value)
                                tableUpvalue.Scanned = {}
                                storage.Upvalues[index] = tableUpvalue
                            end

                            tableUpvalue.Scanned[key] = nestedValue
                        end
                    end
                end
            end
        end
    end

    return upvalues, cancelled(true)
end

UpvalueScanner.Scan = scan
UpvalueScanner.RequiredMethods = requiredMethods
return UpvalueScanner
