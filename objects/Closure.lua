local Closure = {}
-- Active views own their models. Completed scans must not retain every closure
-- and its captured environment for the rest of the session.
local closureCache = setmetatable({}, { __mode = "kv" })

local function getClosureEnvironment(data)
    if safeGetEnv then
        return safeGetEnv(data)
    end

    if type(getfenv) ~= "function" then
        return nil
    end

    local ran, env = pcall(getfenv, data)

    if ran then
        return env
    end
end

local function getClosureScript(data)
    if safeGetClosureScript then
        return safeGetClosureScript(data)
    end
end

function Closure.new(data)
    if closureCache[data] then
        return closureCache[data]
    end

    local closure = {}
    local infoRan, info = pcall(getInfo, data, "n")
    info = infoRan and info or nil
    local name = type(info) == "table" and info.name or ""
    name = type(name) == "string" and name or ""

    closure.Name = (name ~= "" and name) or "Unnamed function"
    closure.Data = data
    closure.Environment = getClosureEnvironment(data)
    closure.Script = getClosureScript(data)
    closure.Upvalues = {}
    closure.Constants = {}
    closure.TemporaryUpvalues = {}
    closure.TemporaryConstants = {}

    closureCache[data] = closure
    return closure
end

return Closure
