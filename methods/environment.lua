local client = game:GetService("Players").LocalPlayer
local control = client and client:FindFirstChild("PlayerScripts") and client.PlayerScripts:FindFirstChild("Control Script")

local methods = {}

local function safeGetEnv(target)
    if type(getfenv) ~= "function" then
        return nil
    end

    local ran, env = pcall(getfenv, target)

    if ran and type(env) == "table" then
        return env
    end

    return nil
end

local function safeGetClosureScript(target)
    local env = safeGetEnv(target)
    local script = env and rawget(env, "script")

    if typeof(script) == "Instance" then
        return script
    end

    return nil
end

local function secureCall(closure, ...)
    if type(getfenv) ~= "function" or type(setfenv) ~= "function" then
        return closure(...)
    end

    local env = getfenv(1)
    local renv = getrenv and getrenv() or env
    local arguments = table.pack(...)

    setfenv(1, setmetatable({ script = script }, {
        __index = renv
    }))

    local results = table.pack(pcall(function()
        if syn and syn.secure_call and control then
            return syn.secure_call(closure, control, table.unpack(arguments, 1, arguments.n))
        end

        return closure(table.unpack(arguments, 1, arguments.n))
    end))

    setfenv(1, env)

    if not results[1] then
        error(results[2], 0)
    end

    return table.unpack(results, 2, results.n)
end

methods.safeGetEnv = safeGetEnv
methods.safeGetClosureScript = safeGetClosureScript
methods.secureCall = secureCall
return methods
