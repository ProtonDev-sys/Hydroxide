local ModuleScript = {}

function ModuleScript.new(instance, closure)
    local moduleScript = {}
    closure = closure or getScriptClosure(instance)

    local constantsRan, constants = pcall(getConstants, closure)
    local protosRan, protos = pcall(getProtos, closure)

    moduleScript.Instance = instance
    moduleScript.Constants = constantsRan and constants or {}
    moduleScript.Protos = protosRan and protos or {}
    --moduleScript.ReturnValue = require(instance) // causes detection

    return moduleScript
end

return ModuleScript
