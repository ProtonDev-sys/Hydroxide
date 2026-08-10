local ModuleScript = {}

function ModuleScript.new(instance)
    local moduleScript = {}

    moduleScript.Instance = instance
    moduleScript.Source = nil
    moduleScript.SourceError = nil
    moduleScript.LoadedSource = false
    moduleScript.FunctionSources = setmetatable({}, { __mode = "k" })
    moduleScript.Decompile = ModuleScript.decompile

    return moduleScript
end

function ModuleScript.decompile(moduleScript, target)
    if target then
        local cached = moduleScript.FunctionSources[target]

        if cached then
            return cached.Source, cached.Error
        end
    elseif moduleScript.LoadedSource then
        return moduleScript.Source, moduleScript.SourceError
    end

    if type(decompile) ~= "function" then
        local sourceError = "decompile is not available in this executor"

        if target then
            moduleScript.FunctionSources[target] = {
                Source = nil,
                Error = sourceError
            }
        else
            moduleScript.Source = nil
            moduleScript.SourceError = sourceError
            moduleScript.LoadedSource = true
        end

        return nil, sourceError
    end

    local subject = target or moduleScript.Instance
    local ran, source = pcall(decompile, subject)
    local sourceError

    if not ran or type(source) ~= "string" or source == "" then
        sourceError = ran and "Decompiler did not return text" or tostring(source)
        source = nil
    end

    if target then
        moduleScript.FunctionSources[target] = {
            Source = source,
            Error = sourceError
        }
    else
        moduleScript.Source = source
        moduleScript.SourceError = sourceError
        moduleScript.LoadedSource = true
    end

    return source, sourceError
end

return ModuleScript
