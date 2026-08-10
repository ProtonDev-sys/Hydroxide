local ConstantScanner = {}
local Closure = import("objects/Closure")
local Constant = import("objects/Constant")

local requiredMethods = {
    ["getLuaClosures"] = true,
    ["getInfo"] = true,
    ["getConstant"] = true,
    ["setConstant"] = true,
    ["getConstants"] = true
}

local function getClosureName(closure)
    local ran, info = pcall(getInfo, closure, "n")
    return ran and info and info.name or ""
end

local function compareConstant(query, loweredQuery, constant)
    local constantType = type(constant)

    if constantType == "string" then
        return query == constant or constant:lower():find(loweredQuery, 1, true) ~= nil
    elseif constantType == "number" then
        return tonumber(query) == constant or ("%.2f"):format(constant) == query
    elseif constantType == "userdata" then
        return toString(constant) == query
    elseif constantType == "function" then
        local closureName = getClosureName(constant)
        return query == closureName or closureName:lower():find(loweredQuery, 1, true) ~= nil
    end

    return false
end

local function scan(query)
    local constants = {}
    query = query or ""
    local loweredQuery = query:lower()

    for _, closure in pairs(getLuaClosures()) do
        local ran, closureConstants = pcall(getConstants, closure)

        if ran and type(closureConstants) == "table" then
            for index, constant in pairs(closureConstants) do
                if compareConstant(query, loweredQuery, constant) then
                    local storage = constants[closure]

                    if not storage then
                        storage = Closure.new(closure)
                        constants[closure] = storage
                    end

                    storage.Constants[index] = Constant.new(storage, index, constant)
                end
            end
        end
    end

    return constants
end

ConstantScanner.Scan = scan
ConstantScanner.RequiredMethods = requiredMethods
return ConstantScanner
