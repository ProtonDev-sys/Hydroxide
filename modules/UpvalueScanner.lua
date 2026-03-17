local UpvalueScanner = {}
local Closure = import("objects/Closure")
local Upvalue = import("objects/Upvalue")

local requiredMethods = {
    ["getGc"] = true,
    ["getInfo"] = true,
    ["isXClosure"] = true,
    ["getUpvalue"] = true,
    ["setUpvalue"] = true,
    ["getUpvalues"] = true
}

local function compareUpvalue(query, upvalue, ignoreNumberMatch)
    local upvalueType = type(upvalue)
    local loweredQuery = query:lower()

    if upvalueType == "string" then
        local loweredValue = upvalue:lower()
        return query == upvalue or loweredValue:find(loweredQuery, 1, true) ~= nil
    elseif upvalueType == "number" and not ignoreNumberMatch then
        local numericQuery = tonumber(query)
        return numericQuery == upvalue or ("%.2f"):format(upvalue) == query
    elseif upvalueType == "boolean" then
        return tostring(upvalue) == loweredQuery
    elseif upvalueType == "userdata" then
        if typeof(upvalue) == "Instance" then
            local instanceName = upvalue.Name
            return instanceName == query or instanceName:lower():find(loweredQuery, 1, true) ~= nil
        end

        return toString(upvalue) == query
    elseif upvalueType == "function" then
        local closureName = getInfo(upvalue).name or ""
        local loweredName = closureName:lower()

        return query == closureName or loweredName:find(loweredQuery, 1, true) ~= nil
    end

    return false
end

local function scan(query, deepSearch)
    local upvalues = {}

    for _, closure in pairs(getGc()) do
        if type(closure) == "function" and not isXClosure(closure) and not upvalues[closure] then
            for index, value in pairs(getUpvalues(closure)) do
                local valueType = type(value)

                if valueType ~= "table" and compareUpvalue(query, value) then
                    local storage = upvalues[closure]

                    if not storage then
                        storage = Closure.new(closure)
                        upvalues[closure] = storage
                    end

                    storage.Upvalues[index] = Upvalue.new(storage, index, value)
                elseif deepSearch and valueType == "table" then
                    local storage = upvalues[closure]
                    local tableUpvalue

                    for key, nestedValue in pairs(value) do
                        if (key ~= value and nestedValue ~= value) and (compareUpvalue(query, key, true) or compareUpvalue(query, nestedValue)) then
                            if not storage then
                                storage = Closure.new(closure)
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

    return upvalues
end

UpvalueScanner.Scan = scan
UpvalueScanner.RequiredMethods = requiredMethods
return UpvalueScanner
