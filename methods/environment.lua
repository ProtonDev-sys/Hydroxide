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

methods.safeGetEnv = safeGetEnv
methods.safeGetClosureScript = safeGetClosureScript
return methods
