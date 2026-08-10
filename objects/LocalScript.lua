local LocalScript = {}

function LocalScript.new(instance, closure, scriptEnvironment)
    local localScript = {}
    closure = closure or getScriptClosure(instance)

    localScript.Instance = instance
    localScript.Environment = scriptEnvironment or getSenv(instance)

    local constantsRan, constants = pcall(getConstants, closure)
    local protosRan, protos = pcall(getProtos, closure)

    localScript.Constants = constantsRan and constants or {}
    localScript.Protos = protosRan and protos or {}

    return localScript
end

return LocalScript
