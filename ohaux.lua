local aux = {}

local getGc = getgc
local filterGc = filtergc
local getInfo = debug.getinfo or getinfo
local getUpvalue = debug.getupvalue or getupvalue or getupval
local getConstants = debug.getconstants or getconstants or getconsts
local isXClosure = isexecutorclosure or is_synapse_function or issentinelclosure or is_protosmasher_closure or is_sirhurt_closure or istempleclosure or checkclosure
local isLClosure = islclosure or is_l_closure or (iscclosure and function(closure)
    return not iscclosure(closure)
end)

assert(getGc and getInfo and getUpvalue and getConstants and isXClosure, "Your exploit is not supported")

local placeholderUserdataConstant = newproxy(false)

local function safeGetEnv(target)
    if type(getfenv) ~= "function" then
        return nil
    end

    local ran, env = pcall(getfenv, target)

    if ran and type(env) == "table" then
        return env
    end
end

local function safeGetClosureScript(target)
    local env = safeGetEnv(target)
    local script = env and rawget(env, "script")

    if typeof(script) == "Instance" then
        return script
    end

    return nil
end

local function matchConstants(closure, list)
    if not list then
        return true
    end

    local ran, constants = pcall(getConstants, closure)

    if not ran or type(constants) ~= "table" then
        return false
    end

    for index, value in pairs(list) do
        if constants[index] ~= value and value ~= placeholderUserdataConstant then
            return false
        end
    end

    return true
end

local function getLuaClosures()
    if filterGc then
        local ran, closures = pcall(filterGc, "function", {
            IgnoreExecutor = true
        }, false)

        if ran and type(closures) == "table" then
            local filtered = {}

            for _, closure in pairs(closures) do
                if not isLClosure or isLClosure(closure) then
                    filtered[#filtered + 1] = closure
                end
            end

            return filtered
        end
    end

    local closures = {}

    for _, object in pairs(getGc(false)) do
        if type(object) == "function"
            and (not isLClosure or isLClosure(object))
            and not isXClosure(object)
        then
            closures[#closures + 1] = object
        end
    end

    return closures
end

local function searchClosure(script, name, upvalueIndex, constants)
    for _, closure in pairs(getLuaClosures()) do
        local parentScript = safeGetClosureScript(closure)
        local matchesScript = script == parentScript

        if script == nil then
            matchesScript = parentScript == nil or parentScript.Parent == nil
        end

        if matchesScript then
            local infoRan, info = pcall(getInfo, closure)
            local closureName = infoRan and info and info.name or ""
            local upvalueCount = infoRan and info and tonumber(info.nups)
            local hasUpvalue = upvalueCount and upvalueIndex >= 1 and upvalueIndex <= upvalueCount

            if not hasUpvalue and upvalueCount == nil then
                local upvalueRan, upvalue = pcall(getUpvalue, closure, upvalueIndex)
                hasUpvalue = upvalueRan and upvalue ~= nil
            end

            if hasUpvalue
                and ((name and name ~= "Unnamed function") and closureName == name)
                and matchConstants(closure, constants)
            then
                return closure
            elseif hasUpvalue and (not name or name == "Unnamed function") and matchConstants(closure, constants) then
                return closure
            end
        end
    end
end

aux.placeholderUserdataConstant = placeholderUserdataConstant
aux.safeGetEnv = safeGetEnv
aux.safeGetClosureScript = safeGetClosureScript
aux.searchClosure = searchClosure

return aux
