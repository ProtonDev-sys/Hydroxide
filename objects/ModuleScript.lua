local ModuleScript = {}

function ModuleScript.new(instance)
    local moduleScript = {}

    moduleScript.Instance = instance
    moduleScript.Decompile = ModuleScript.decompile

    return moduleScript
end

function ModuleScript.decompile(moduleScript, target)
    if type(decompile) ~= "function" then
        return nil, "decompile is not available in this executor"
    end

    local subject = target or moduleScript.Instance
    local ran, source = pcall(decompile, subject)

    if ran and type(source) == "string" then
        return source
    end

    return nil, ran and "Decompiler did not return text" or tostring(source)
end

return ModuleScript
