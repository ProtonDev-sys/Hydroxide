local LocalScript = {}

local function unavailable(name)
    return nil, name .. " is not available in this executor"
end

function LocalScript.new(instance, closure, scriptEnvironment)
    local localScript = {}

    localScript.Instance = instance
    localScript.Closure = closure
    localScript.Environment = scriptEnvironment
    localScript.Constants = {}
    localScript.Protos = {}
    localScript.LoadedConstants = false
    localScript.LoadedProtos = false
    localScript.LoadedEnvironment = scriptEnvironment ~= nil
    localScript.LoadClosure = LocalScript.loadClosure
    localScript.LoadEnvironment = LocalScript.loadEnvironment
    localScript.LoadConstants = LocalScript.loadConstants
    localScript.LoadProtos = LocalScript.loadProtos
    localScript.Decompile = LocalScript.decompile

    return localScript
end

function LocalScript.loadClosure(localScript)
    if localScript.Closure then
        return localScript.Closure
    elseif type(getScriptClosure) ~= "function" then
        return unavailable("getScriptClosure")
    end

    local ran, closure = pcall(getScriptClosure, localScript.Instance)

    if not ran or type(closure) ~= "function" then
        return nil, ran and "Script closure was not returned" or tostring(closure)
    end

    localScript.Closure = closure
    return closure
end

function LocalScript.loadEnvironment(localScript)
    if localScript.LoadedEnvironment then
        return localScript.Environment
    elseif type(getSenv) ~= "function" then
        return unavailable("getSenv")
    end

    local ran, environment = pcall(getSenv, localScript.Instance)

    if not ran or type(environment) ~= "table" then
        localScript.Environment = {}
        localScript.LoadedEnvironment = true
        return nil, ran and "Script environment was not returned" or tostring(environment)
    end

    localScript.Environment = environment
    localScript.LoadedEnvironment = true
    return environment
end

function LocalScript.loadConstants(localScript)
    if localScript.LoadedConstants then
        return localScript.Constants
    elseif type(getConstants) ~= "function" then
        return unavailable("getConstants")
    end

    local closure, closureError = localScript:LoadClosure()

    if not closure then
        return nil, closureError
    end

    local ran, constants = pcall(getConstants, closure)

    if not ran or type(constants) ~= "table" then
        localScript.Constants = {}
        localScript.LoadedConstants = true
        return nil, ran and "Constants were not returned" or tostring(constants)
    end

    localScript.Constants = constants
    localScript.LoadedConstants = true
    return constants
end

function LocalScript.loadProtos(localScript)
    if localScript.LoadedProtos then
        return localScript.Protos
    elseif type(getProtos) ~= "function" then
        return unavailable("getProtos")
    end

    local closure, closureError = localScript:LoadClosure()

    if not closure then
        return nil, closureError
    end

    local ran, protos = pcall(getProtos, closure)

    if not ran or type(protos) ~= "table" then
        localScript.Protos = {}
        localScript.LoadedProtos = true
        return nil, ran and "Protos were not returned" or tostring(protos)
    end

    localScript.Protos = protos
    localScript.LoadedProtos = true
    return protos
end

function LocalScript.decompile(localScript, target)
    if type(decompile) ~= "function" then
        return unavailable("decompile")
    end

    local subject = target or localScript.Instance
    local ran, source = pcall(decompile, subject)

    if ran and type(source) == "string" then
        return source
    elseif target then
        return nil, ran and "Decompiler did not return text" or tostring(source)
    end

    local closure, closureError = localScript:LoadClosure()

    if not closure then
        return nil, closureError or (ran and "Decompiler did not return text" or tostring(source))
    end

    ran, source = pcall(decompile, closure)

    if ran and type(source) == "string" then
        return source
    end

    return nil, ran and "Decompiler did not return text" or tostring(source)
end

return LocalScript
