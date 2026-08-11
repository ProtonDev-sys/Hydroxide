local ModuleScript = {}

local function unavailable(name)
    return nil, name .. " is not available in this executor"
end

local function normalizeSourceLimit(value)
    local settings = oh and oh.Settings or {}
    value = tonumber(value) or tonumber(settings.MaxInspectorBytes or settings.maxInspectorBytes) or 524288
    return math.max(1024, math.min(8388608, math.floor(value)))
end

local function boundSource(source, maximum)
    if type(source) ~= "string" or #source <= maximum then
        return source, true
    end

    local marker = "\n-- ... source truncated by the configured safety limit ..."
    return source:sub(1, math.max(0, maximum - #marker)) .. marker, false
end

local function functionCacheLimits()
    local settings = oh and oh.Settings or {}
    local entries = tonumber(settings.MaxFunctionSourceCacheEntries or settings.maxFunctionSourceCacheEntries) or 16
    local bytes = tonumber(settings.MaxFunctionSourceCacheBytes or settings.maxFunctionSourceCacheBytes) or 1048576
    return math.max(1, math.min(128, math.floor(entries))), math.max(32768, math.min(8388608, math.floor(bytes)))
end

local function functionCacheEntryBytes(entry)
    return #(type(entry.Source) == "string" and entry.Source or "") + #(type(entry.Error) == "string" and entry.Error or "")
end

local function sharedFunctionCacheBudget()
    local budget = oh and oh.FunctionSourceCache

    if budget and type(budget.Reserve) == "function" and type(budget.Release) == "function" then
        return budget
    end
end

local function removeFunctionSource(moduleScript, target, expected, releaseBudget)
    local cached = moduleScript.FunctionSources[target]

    if not cached or (expected and cached ~= expected) then
        return
    end

    moduleScript.FunctionSources[target] = nil
    moduleScript.FunctionSourceBytes = math.max(0, moduleScript.FunctionSourceBytes - functionCacheEntryBytes(cached))

    for index, cachedTarget in ipairs(moduleScript.FunctionSourceOrder) do
        if cachedTarget == target then
            table.remove(moduleScript.FunctionSourceOrder, index)
            break
        end
    end

    if releaseBudget and cached.BudgetToken then
        local budget = sharedFunctionCacheBudget()

        if budget then
            budget:Release(cached.BudgetToken, false)
        end
    end

    cached.BudgetToken = nil
end

local function cacheFunctionSource(moduleScript, target, entry)
    local existing = moduleScript.FunctionSources[target]

    if existing then
        removeFunctionSource(moduleScript, target, existing, true)
    end

    local maximumEntries, maximumBytes = functionCacheLimits()
    local entryBytes = functionCacheEntryBytes(entry)

    if entryBytes > maximumBytes then
        return
    end

    local budget = sharedFunctionCacheBudget()

    if budget then
        local token = budget:Reserve(entryBytes, function()
            removeFunctionSource(moduleScript, target, entry, false)
        end)

        if not token then
            return
        end

        entry.BudgetToken = token
    end

    moduleScript.FunctionSources[target] = entry
    moduleScript.FunctionSourceOrder[#moduleScript.FunctionSourceOrder + 1] = target
    moduleScript.FunctionSourceBytes = moduleScript.FunctionSourceBytes + entryBytes

    while #moduleScript.FunctionSourceOrder > maximumEntries or moduleScript.FunctionSourceBytes > maximumBytes do
        local evictedTarget = moduleScript.FunctionSourceOrder[1]
        local evicted = moduleScript.FunctionSources[evictedTarget]

        if evicted then
            removeFunctionSource(moduleScript, evictedTarget, evicted, true)
        else
            table.remove(moduleScript.FunctionSourceOrder, 1)
        end
    end
end

function ModuleScript.clearFunctionSourceCache(moduleScript)
    while #moduleScript.FunctionSourceOrder > 0 do
        local target = moduleScript.FunctionSourceOrder[1]
        removeFunctionSource(moduleScript, target, nil, true)
    end
end

function ModuleScript.new(instance, closure, scriptEnvironment)
    local moduleScript = {}

    moduleScript.Instance = instance
    moduleScript.Closure = closure
    moduleScript.ClosureError = nil
    moduleScript.Environment = scriptEnvironment
    moduleScript.EnvironmentError = nil
    moduleScript.Constants = {}
    moduleScript.ConstantsError = nil
    moduleScript.Protos = {}
    moduleScript.ProtosError = nil
    moduleScript.Source = nil
    moduleScript.SourceError = nil
    moduleScript.SourceLimit = 0
    moduleScript.SourceComplete = false
    moduleScript.FunctionSources = setmetatable({}, { __mode = "k" })
    moduleScript.FunctionSourceOrder = {}
    moduleScript.FunctionSourceBytes = 0
    moduleScript.LoadedClosure = closure ~= nil
    moduleScript.LoadedConstants = false
    moduleScript.LoadedProtos = false
    moduleScript.LoadedEnvironment = scriptEnvironment ~= nil
    moduleScript.LoadedSource = false
    moduleScript.LoadClosure = ModuleScript.loadClosure
    moduleScript.LoadEnvironment = ModuleScript.loadEnvironment
    moduleScript.LoadConstants = ModuleScript.loadConstants
    moduleScript.LoadProtos = ModuleScript.loadProtos
    moduleScript.Decompile = ModuleScript.decompile
    moduleScript.ClearFunctionSourceCache = ModuleScript.clearFunctionSourceCache

    return moduleScript
end

function ModuleScript.loadClosure(moduleScript)
    if moduleScript.LoadedClosure then
        return moduleScript.Closure, moduleScript.ClosureError
    elseif type(getScriptClosure) ~= "function" then
        moduleScript.LoadedClosure = true
        moduleScript.ClosureError = "getScriptClosure is not available in this executor"
        return nil, moduleScript.ClosureError
    end

    local ran, closure = pcall(getScriptClosure, moduleScript.Instance)
    moduleScript.LoadedClosure = true

    if not ran or type(closure) ~= "function" then
        moduleScript.ClosureError = ran and "Module closure was not returned" or tostring(closure)
        return nil, moduleScript.ClosureError
    end

    moduleScript.Closure = closure
    moduleScript.ClosureError = nil
    return closure
end

function ModuleScript.loadEnvironment(moduleScript)
    if moduleScript.LoadedEnvironment then
        if moduleScript.EnvironmentError then
            return nil, moduleScript.EnvironmentError
        end

        return moduleScript.Environment
    end

    local environmentGetters = {}

    -- Potassium documents getsenv for both running scripts and ModuleScripts.
    -- Keep getMenv as a legacy fallback, but never let a broken legacy alias
    -- mask a working documented implementation.
    if type(getSenv) == "function" then
        environmentGetters[#environmentGetters + 1] = { Name = "getSenv", Callback = getSenv }
    end

    if type(getMenv) == "function" and getMenv ~= getSenv then
        environmentGetters[#environmentGetters + 1] = { Name = "getMenv", Callback = getMenv }
    end

    if #environmentGetters == 0 then
        moduleScript.LoadedEnvironment = true
        moduleScript.EnvironmentError = "getMenv/getSenv is not available in this executor"
        return nil, moduleScript.EnvironmentError
    end

    local failures = {}

    for _, getter in ipairs(environmentGetters) do
        local ran, environment = pcall(getter.Callback, moduleScript.Instance)

        if ran and type(environment) == "table" then
            moduleScript.LoadedEnvironment = true
            moduleScript.Environment = environment
            moduleScript.EnvironmentError = nil
            return environment
        end

        failures[#failures + 1] = getter.Name .. ": "
            .. (ran and "Module environment was not returned" or tostring(environment))
    end

    moduleScript.LoadedEnvironment = true
    moduleScript.Environment = {}
    moduleScript.EnvironmentError = table.concat(failures, "; ")
    return nil, moduleScript.EnvironmentError
end

function ModuleScript.loadConstants(moduleScript)
    if moduleScript.LoadedConstants then
        if moduleScript.ConstantsError then
            return nil, moduleScript.ConstantsError
        end

        return moduleScript.Constants
    elseif type(getConstants) ~= "function" then
        moduleScript.LoadedConstants = true
        moduleScript.ConstantsError = "getConstants is not available in this executor"
        return nil, moduleScript.ConstantsError
    end

    local closure, closureError = moduleScript:LoadClosure()

    if not closure then
        moduleScript.LoadedConstants = true
        moduleScript.ConstantsError = closureError
        return nil, closureError
    end

    local ran, constants = pcall(getConstants, closure)
    moduleScript.LoadedConstants = true

    if not ran or type(constants) ~= "table" then
        moduleScript.Constants = {}
        moduleScript.ConstantsError = ran and "Constants were not returned" or tostring(constants)
        return nil, moduleScript.ConstantsError
    end

    moduleScript.Constants = constants
    moduleScript.ConstantsError = nil
    return constants
end

function ModuleScript.loadProtos(moduleScript)
    if moduleScript.LoadedProtos then
        if moduleScript.ProtosError then
            return nil, moduleScript.ProtosError
        end

        return moduleScript.Protos
    elseif type(getProtos) ~= "function" then
        moduleScript.LoadedProtos = true
        moduleScript.ProtosError = "getProtos is not available in this executor"
        return nil, moduleScript.ProtosError
    end

    local closure, closureError = moduleScript:LoadClosure()

    if not closure then
        moduleScript.LoadedProtos = true
        moduleScript.ProtosError = closureError
        return nil, closureError
    end

    local ran, protos = pcall(getProtos, closure)
    moduleScript.LoadedProtos = true

    if not ran or type(protos) ~= "table" then
        moduleScript.Protos = {}
        moduleScript.ProtosError = ran and "Protos were not returned" or tostring(protos)
        return nil, moduleScript.ProtosError
    end

    moduleScript.Protos = protos
    moduleScript.ProtosError = nil
    return protos
end

function ModuleScript.decompile(moduleScript, target, maximumBytes)
    local maximum = normalizeSourceLimit(maximumBytes)

    if target then
        local cached = moduleScript.FunctionSources[target]

        if cached and (cached.Complete or (tonumber(cached.Limit) or 0) >= maximum) then
            local source = cached.Source and select(1, boundSource(cached.Source, maximum)) or nil
            return source, cached.Error
        end
    elseif moduleScript.LoadedSource
        and (moduleScript.SourceComplete or (tonumber(moduleScript.SourceLimit) or 0) >= maximum)
    then
        local source = moduleScript.Source and select(1, boundSource(moduleScript.Source, maximum)) or nil
        return source, moduleScript.SourceError
    end

    if type(decompile) ~= "function" then
        local _, sourceError = unavailable("decompile")

        if target then
            cacheFunctionSource(moduleScript, target, {
                Source = nil,
                Error = sourceError,
                Limit = maximum,
                Complete = true
            })
        else
            moduleScript.Source = nil
            moduleScript.SourceError = sourceError
            moduleScript.SourceLimit = maximum
            moduleScript.SourceComplete = true
            moduleScript.LoadedSource = true
        end

        return nil, sourceError
    end

    local subject = target or moduleScript.Instance
    local ran, source = pcall(decompile, subject)
    local sourceError

    if (not ran or type(source) ~= "string" or source == "") and not target then
        local closure, closureError = moduleScript:LoadClosure()

        if closure then
            ran, source = pcall(decompile, closure)
        else
            sourceError = closureError
        end
    end

    if not ran or type(source) ~= "string" or source == "" then
        sourceError = sourceError or (ran and "Decompiler did not return text" or tostring(source))
        source = nil
    end

    local complete = false

    if source then
        source, complete = boundSource(source, maximum)
    end

    if target then
        cacheFunctionSource(moduleScript, target, {
            Source = source,
            Error = sourceError,
            Limit = maximum,
            Complete = complete
        })
    else
        moduleScript.Source = source
        moduleScript.SourceError = sourceError
        moduleScript.SourceLimit = maximum
        moduleScript.SourceComplete = complete
        moduleScript.LoadedSource = true
    end

    return source, sourceError
end

return ModuleScript
