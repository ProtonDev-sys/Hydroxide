local ConstantScanner = {}
local Closure = import("objects/Closure")
local Constant = import("objects/Constant")

local requiredMethods = {
    ["getGc"] = true,
    ["getInfo"] = true,
    ["isXClosure"] = true,
    ["isLClosure"] = true,
    ["getConstant"] = true,
    ["setConstant"] = true,
    ["getConstants"] = true
}

local function compareConstant(query, constant)
    local constantType = type(constant)
    local loweredQuery = query:lower()

    if constantType == "string" then
        return query == constant or constant:lower():find(loweredQuery, 1, true) ~= nil
    elseif constantType == "number" then
        return tonumber(query) == constant or ("%.2f"):format(constant) == query
    elseif constantType == "userdata" then
        return toString(constant) == query
    elseif constantType == "function" then
        local closureName = getInfo(constant).name or ""
        return query == closureName or closureName:lower():find(loweredQuery, 1, true) ~= nil
    end

    return false
end

local function scan(query)
    local constants = {}

    for _, closure in pairs(getGc()) do
        if type(closure) == "function" and not isXClosure(closure) and isLClosure(closure) and not constants[closure] then
            for index, constant in pairs(getConstants(closure)) do
                if compareConstant(query, constant) then
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
