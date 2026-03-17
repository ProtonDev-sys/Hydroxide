local aux = {}

local getGc = getgc
local getInfo = debug.getinfo or getinfo
local getUpvalue = debug.getupvalue or getupvalue or getupval
local getConstants = debug.getconstants or getconstants or getconsts
local isXClosure = isexecutorclosure or is_synapse_function or issentinelclosure or is_protosmasher_closure or is_sirhurt_closure or istempleclosure or checkclosure
local isLClosure = islclosure or is_l_closure or (iscclosure and function(closure)
    return not iscclosure(closure)
end)

assert(getGc and getInfo and getConstants and isXClosure, "Your exploit is not supported")

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

    local constants = getConstants(closure)

    for index, value in pairs(list) do
        if constants[index] ~= value and value ~= placeholderUserdataConstant then
            return false
        end
    end

    return true
end

local function searchClosure(script, name, upvalueIndex, constants)
    for _, closure in pairs(getGc()) do
        local parentScript = safeGetClosureScript(closure)
        local matchesScript = script == parentScript

        if script == nil then
            matchesScript = parentScript == nil or parentScript.Parent == nil
        end

        if type(closure) == "function" and
            isLClosure(closure) and
            not isXClosure(closure) and
            matchesScript and
            pcall(getUpvalue, closure, upvalueIndex)
        then
            local closureName = getInfo(closure).name

            if ((name and name ~= "Unnamed function") and closureName == name) and matchConstants(closure, constants) then
                return closure
            elseif (not name or name == "Unnamed function") and matchConstants(closure, constants) then
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
