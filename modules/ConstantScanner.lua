local ConstantScanner = {}
local Closure = import("objects/Closure")
local Constant = import("objects/Constant")
local checkpoint = import("modules/Scanner").checkpoint

local requiredMethods = {
    ["getLuaClosures"] = true,
    ["getInfo"] = true,
    ["getConstant"] = true,
    ["setConstant"] = true,
    ["getConstants"] = true
}

local function getClosureName(closure)
    local ran, info = pcall(getInfo, closure, "n")
    local name = ran and type(info) == "table" and info.name
    return type(name) == "string" and name or ""
end

local function compareConstant(query, loweredQuery, constant)
    local constantType = type(constant)

    if constantType == "string" then
        return query == constant or constant:lower():find(loweredQuery, 1, true) ~= nil
    elseif constantType == "number" then
        return tonumber(query) == constant or ("%.2f"):format(constant) == query
    elseif constantType == "boolean" then
        return tostring(constant) == loweredQuery
    elseif constantType == "userdata" then
        local ran, text = pcall(toString, constant)
        return ran and text == query
    elseif constantType == "function" then
        local closureName = getClosureName(constant)
        return query == closureName or closureName:lower():find(loweredQuery, 1, true) ~= nil
    end

    return false
end

local function scan(query, options)
    local constants = {}
    query = tostring(query or "")
    local loweredQuery = query:lower()
    local cancelled = checkpoint(options)
    if cancelled(true) then
        return constants, true
    end
    local closures = getLuaClosures()
    assert(type(closures) == "table", "getLuaClosures did not return a table")
    if cancelled(true) then
        return constants, true
    end
    local seen = {}

    for _, closure in next, closures do
        if cancelled() then
            return constants, true
        end
        local ran, closureConstants = false, nil
        if type(closure) == "function" and not seen[closure] then
            seen[closure] = true
            ran, closureConstants = pcall(getConstants, closure)
        end
        if cancelled(true) then
            return constants, true
        end

        if ran and type(closureConstants) == "table" then
            for index, constant in next, closureConstants do
                if cancelled() then
                    return constants, true
                end
                if compareConstant(query, loweredQuery, constant) then
                    local storage = constants[closure]

                    if not storage then
                        storage = Closure.new(closure)
                        storage.Constants = {}
                        storage.TemporaryConstants = {}
                        constants[closure] = storage
                    end

                    storage.Constants[index] = Constant.new(storage, index, constant)
                end
            end
        end
    end

    return constants, cancelled(true)
end

ConstantScanner.Scan = scan
ConstantScanner.RequiredMethods = requiredMethods
return ConstantScanner
