local root = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\][^/\\]+$")) or ""
assert(root, "unable to locate repository root")

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
    end
end

local closureLoads = 0
local constantLoads = 0
local protoLoads = 0
local environmentLoads = 0
local instanceDecompileLoads = 0
local functionDecompileLoads = 0
local scriptClosure = function() end

_G.getScriptClosure = function()
    closureLoads = closureLoads + 1
    return scriptClosure
end
_G.getConstants = function(closure)
    assertEqual(closure, scriptClosure, "constants closure")
    constantLoads = constantLoads + 1
    return { "constant" }
end
_G.getProtos = function(closure)
    assertEqual(closure, scriptClosure, "protos closure")
    protoLoads = protoLoads + 1
    return { function() end }
end
_G.getSenv = function()
    environmentLoads = environmentLoads + 1
    return { scriptValue = true }
end
_G.decompile = function(target)
    if target == scriptClosure then
        functionDecompileLoads = functionDecompileLoads + 1
        return "-- closure source"
    end

    instanceDecompileLoads = instanceDecompileLoads + 1
    return "-- instance source"
end

local imports = {}
_G.import = function(path)
    if not imports[path] then
        imports[path] = dofile(root .. path .. ".lua")
    end
    return imports[path]
end
local LocalScript = import("objects/LocalScript")
local ModuleScript = import("objects/ModuleScript")
local localInstance = {}
local moduleInstance = {}
local localModel = LocalScript.new(localInstance)
local moduleModel = ModuleScript.new(moduleInstance)

assertEqual(closureLoads, 0, "models do not eagerly load closures")
assertEqual(constantLoads, 0, "models do not eagerly load constants")
assertEqual(protoLoads, 0, "models do not eagerly load protos")

assertEqual(#localModel:LoadConstants(), 1, "local constants load")
assertEqual(#localModel:LoadProtos(), 1, "local protos load")
assertEqual(closureLoads, 1, "local closure cached across lazy reads")
assertEqual(constantLoads, 1, "local constants loaded once")
assertEqual(protoLoads, 1, "local protos loaded once")
localModel:LoadConstants()
localModel:LoadProtos()
assertEqual(constantLoads, 1, "local constants cache reused")
assertEqual(protoLoads, 1, "local protos cache reused")
assertEqual(localModel:LoadEnvironment().scriptValue, true, "local environment load")
localModel:LoadEnvironment()
assertEqual(environmentLoads, 1, "local environment cache reused")
assertEqual(localModel:Decompile(), "-- instance source", "local instance decompile preferred")
assertEqual(localModel:Decompile(scriptClosure), "-- closure source", "local function decompile")
localModel:Decompile()
localModel:Decompile(scriptClosure)
assertEqual(closureLoads, 1, "local decompile cache reuses existing closure")
assertEqual(instanceDecompileLoads, 1, "local script source cache reused")
assertEqual(functionDecompileLoads, 1, "local function source cache reused")

assertEqual(moduleModel:Decompile(), "-- instance source", "module instance decompile preferred")
moduleModel:Decompile()
assertEqual(instanceDecompileLoads, 2, "module source cache reused")
assertEqual(#moduleModel:LoadConstants(), 1, "module constants load")
assertEqual(#moduleModel:LoadProtos(), 1, "module protos load")
assertEqual(moduleModel:LoadEnvironment().scriptValue, true, "module environment load")
assertEqual(moduleModel:Decompile(scriptClosure), "-- closure source", "module function decompile")
moduleModel:LoadConstants()
moduleModel:LoadProtos()
moduleModel:LoadEnvironment()
moduleModel:Decompile(scriptClosure)
assertEqual(closureLoads, 2, "module closure is loaded once and cached")
assertEqual(constantLoads, 2, "module constants are loaded once")
assertEqual(protoLoads, 2, "module protos are loaded once")
assertEqual(environmentLoads, 2, "module environment is loaded once")
assertEqual(functionDecompileLoads, 2, "module function source is cached")

local moduleEnvironmentLoads = 0
_G.getSenv = nil
_G.getMenv = function(instance)
    assertEqual(instance, moduleInstance, "module environment instance")
    moduleEnvironmentLoads = moduleEnvironmentLoads + 1
    return { moduleValue = true }
end
local menvOnlyModel = ModuleScript.new(moduleInstance)
assertEqual(menvOnlyModel:LoadEnvironment().moduleValue, true, "getMenv-only module environment")
menvOnlyModel:LoadEnvironment()
assertEqual(moduleEnvironmentLoads, 1, "getMenv-only module environment cache reused")
_G.getMenv = nil
_G.getSenv = function()
    environmentLoads = environmentLoads + 1
    return { scriptValue = true }
end

local legacyEnvironmentLoads = 0
local documentedEnvironmentLoads = 0
_G.getMenv = function()
    legacyEnvironmentLoads = legacyEnvironmentLoads + 1
    error("broken legacy getMenv")
end
_G.getSenv = function(instance)
    assertEqual(instance, moduleInstance, "documented module environment instance")
    documentedEnvironmentLoads = documentedEnvironmentLoads + 1
    return { documentedModuleValue = true }
end
local documentedEnvironmentModel = ModuleScript.new(moduleInstance)
assertEqual(
    documentedEnvironmentModel:LoadEnvironment().documentedModuleValue,
    true,
    "documented getSenv preferred when legacy getMenv is also present"
)
assertEqual(documentedEnvironmentLoads, 1, "documented getSenv used once")
assertEqual(legacyEnvironmentLoads, 0, "broken legacy getMenv does not mask documented getSenv")
documentedEnvironmentModel:LoadEnvironment()
assertEqual(documentedEnvironmentLoads, 1, "documented getSenv result is cached")
_G.getMenv = nil
_G.getSenv = function()
    environmentLoads = environmentLoads + 1
    return { scriptValue = true }
end

local boundedDecompileLoads = 0
_G.decompile = function()
    boundedDecompileLoads = boundedDecompileLoads + 1
    return string.rep("x", 4096)
end
local boundedModuleModel = ModuleScript.new({})
local boundedSource = boundedModuleModel:Decompile(nil, 1024)
assertEqual(#boundedSource, 1024, "module source cache is bounded before retention")
assert(boundedSource:find("source truncated", 1, true), "bounded module source reports truncation")
boundedModuleModel:Decompile(nil, 1024)
assertEqual(boundedDecompileLoads, 1, "bounded module source cache is reused at the same limit")
boundedModuleModel:Decompile(nil, 2048)
assertEqual(boundedDecompileLoads, 2, "larger source requests can refresh a truncated cache")
local smallerBoundedSource = boundedModuleModel:Decompile(nil, 1024)
assertEqual(#smallerBoundedSource, 1024, "cached module source is rebound for smaller requests")
assertEqual(boundedDecompileLoads, 2, "smaller source requests reuse the bounded cache")

local boundedLocalModel = LocalScript.new({})
local boundedLocalSource = boundedLocalModel:Decompile(nil, 1024)
assertEqual(#boundedLocalSource, 1024, "local source cache is bounded before retention")
assert(boundedLocalSource:find("source truncated", 1, true), "bounded local source reports truncation")
boundedLocalModel:Decompile(nil, 1024)
assertEqual(boundedDecompileLoads, 3, "bounded local source cache is reused at the same limit")

local function verifyFunctionSourceEviction(model, label)
    local targets = {}
    local calls = setmetatable({}, { __mode = "k" })
    _G.decompile = function(target)
        calls[target] = (calls[target] or 0) + 1
        return "-- cached function source"
    end

    for index = 1, 17 do
        targets[index] = function() return index end
        model:Decompile(targets[index], 1024)
    end

    assertEqual(#model.FunctionSourceOrder, 16, label .. " function-source entry limit")
    model:Decompile(targets[1], 1024)
    assertEqual(calls[targets[1]], 2, label .. " evicts the oldest function source")
end

verifyFunctionSourceEviction(LocalScript.new({}), "local model")
verifyFunctionSourceEviction(ModuleScript.new({}), "module model")

local sharedBudget = { Order = {}, Entries = 0 }
function sharedBudget:Release(token, evict)
    if not token.Active then
        return
    end

    token.Active = false
    self.Entries = self.Entries - 1
    local callback = token.Evict
    token.Evict = nil

    if evict and callback then
        callback()
    end
end
function sharedBudget:Reserve(_bytes, evict)
    local token = { Active = true, Evict = evict }
    self.Order[#self.Order + 1] = token
    self.Entries = self.Entries + 1

    while self.Entries > 2 do
        local oldest = table.remove(self.Order, 1)
        self:Release(oldest, true)
    end

    return token
end

_G.oh = {
    Settings = {
        MaxFunctionSourceCacheEntries = 16,
        MaxFunctionSourceCacheBytes = 1048576
    },
    FunctionSourceCache = sharedBudget
}
local aggregateLocalModel = LocalScript.new({})
local aggregateModuleModel = ModuleScript.new({})
local aggregateFunctions = { function() end, function() end, function() end }
aggregateLocalModel:Decompile(aggregateFunctions[1], 1024)
aggregateModuleModel:Decompile(aggregateFunctions[2], 1024)
aggregateLocalModel:Decompile(aggregateFunctions[3], 1024)
assertEqual(sharedBudget.Entries, 2, "shared function-source cache enforces one aggregate entry budget")
assertEqual(aggregateLocalModel.FunctionSources[aggregateFunctions[1]], nil, "aggregate budget evicts across models")
aggregateLocalModel:ClearFunctionSourceCache()
aggregateModuleModel:ClearFunctionSourceCache()
assertEqual(sharedBudget.Entries, 0, "model cache cleanup releases aggregate budget tokens")
_G.oh = nil

local failingClosureCalls = 0
_G.getScriptClosure = function()
    failingClosureCalls = failingClosureCalls + 1
    return nil
end
_G.decompile = function()
    return nil
end

local failingModel = LocalScript.new({})
local constantsValue, constantsError = failingModel:LoadConstants()
local protosValue, protosError = failingModel:LoadProtos()
local sourceValue, sourceError = failingModel:Decompile()

assertEqual(constantsValue, nil, "failed constants return nil")
assertEqual(constantsError, "Script closure was not returned", "failed constants preserve closure error")
assertEqual(protosValue, nil, "failed protos return nil")
assertEqual(protosError, "Script closure was not returned", "failed protos preserve closure error")
assertEqual(sourceValue, nil, "failed decompile returns nil")
assertEqual(sourceError, "Script closure was not returned", "failed decompile preserves closure error")
assertEqual(failingClosureCalls, 1, "failed closure lookups are cached across inspectors")

failingModel:LoadConstants()
failingModel:LoadProtos()
failingModel:Decompile()
assertEqual(failingClosureCalls, 1, "repeated failed reads do not retry or clear errors")

local failingEnvironmentCalls = 0
_G.getSenv = function()
    failingEnvironmentCalls = failingEnvironmentCalls + 1
    return nil
end

local failingEnvironmentModel = LocalScript.new({})
local environmentValue, environmentError = failingEnvironmentModel:LoadEnvironment()
assertEqual(environmentValue, nil, "failed environment returns nil")
assertEqual(environmentError, "Script environment was not returned", "failed environment preserves error")
failingEnvironmentModel:LoadEnvironment()
assertEqual(failingEnvironmentCalls, 1, "failed environment lookup is cached")

_G.decompile = nil
local unavailableFunction = function() end
local unavailableLocalModel = LocalScript.new({})
local unavailableModuleModel = ModuleScript.new({})
local _, unavailableLocalError = unavailableLocalModel:Decompile()
local _, unavailableFunctionError = unavailableLocalModel:Decompile(unavailableFunction)
local _, unavailableModuleError = unavailableModuleModel:Decompile()

assertEqual(unavailableLocalError, "decompile is not available in this executor", "local source capability error")
assertEqual(unavailableFunctionError, unavailableLocalError, "function source capability error")
assertEqual(unavailableModuleError, unavailableLocalError, "module source capability error")
assertEqual(unavailableLocalModel.LoadedSource, true, "local source capability error cached")
assertEqual(unavailableModuleModel.LoadedSource, true, "module source capability error cached")
assertEqual(
    unavailableLocalModel:Decompile(unavailableFunction),
    nil,
    "cached unavailable function source stays unavailable"
)

local function makeScript(className, name)
    local instance = {
        __instance = true,
        ClassName = className,
        Name = name
    }

    function instance:IsA(targetClass)
        return self.ClassName == targetClass
            or (targetClass == "BaseScript" and (self.ClassName == "LocalScript" or self.ClassName == "Script"))
    end

    return instance
end

_G.typeof = function(value)
    return type(value) == "table" and value.__instance and "Instance" or type(value)
end

local runningLocal = makeScript("LocalScript", "RunningClient")
local runningScript = makeScript("Script", "RunningClientContext")
local loadedModule = makeScript("ModuleScript", "LoadedModule")
_G.getRunningScripts = function()
    return { runningLocal, runningScript, loadedModule, runningLocal }
end
_G.getLoadedModules = function()
    return { loadedModule, runningLocal, loadedModule }
end
_G.getScripts = function()
    error("getscripts must not change running/loaded scanner semantics")
end
local ScriptScanner = import("modules/ScriptScanner")
local ModuleScanner = import("modules/ModuleScanner")
local scriptResults = ScriptScanner.Scan("running")
local moduleResults = ModuleScanner.Scan("loaded")

assertEqual(scriptResults[runningLocal].Instance, runningLocal, "running LocalScript enumerated")
assertEqual(scriptResults[runningScript].Instance, runningScript, "running client-context Script enumerated")
assertEqual(scriptResults[loadedModule], nil, "ModuleScript excluded from ScriptScanner")
assertEqual(moduleResults[loadedModule].Instance, loadedModule, "loaded ModuleScript enumerated")
assertEqual(moduleResults[runningLocal], nil, "LocalScript excluded from ModuleScanner")

local rawScripts = {}
local scriptTotal, scriptCancelled = ScriptScanner.Enumerate("running", function(instance)
    rawScripts[instance] = true
end)
assertEqual(scriptTotal, 2, "script enumeration reports matched instances")
assertEqual(scriptCancelled, false, "script enumeration completes")
assertEqual(rawScripts[runningLocal], true, "script enumeration returns raw LocalScript")
assertEqual(rawScripts[runningScript], true, "script enumeration returns raw client-context Script")

local manyModules = {}

for index = 1, 20 do
    manyModules[index] = makeScript("ModuleScript", "Module" .. index)
end

_G.getLoadedModules = function()
    return manyModules
end

local enumeratedCount = 0
local cancelledTotal, wasCancelled = ModuleScanner.Enumerate("", function()
    enumeratedCount = enumeratedCount + 1
end, {
    YieldEvery = 16,
    IsCancelled = function()
        return enumeratedCount >= 16
    end
})
assertEqual(wasCancelled, true, "module enumeration is cancellable between batches")
assertEqual(cancelledTotal, 16, "module cancellation reports matched rows so far")
assertEqual(enumeratedCount, 16, "module cancellation stops model consumers promptly")

_G.getRunningScripts = function()
    error("running scripts unavailable")
end
local runningOk, runningError = pcall(ScriptScanner.Enumerate, "")
assertEqual(runningOk, false, "script enumeration surfaces runtime API failures")
assert(tostring(runningError):find("running scripts unavailable", 1, true), "script failure preserves its cause")

_G.getLoadedModules = function()
    return nil
end
local modulesOk, modulesError = pcall(ModuleScanner.Enumerate, "")
assertEqual(modulesOk, false, "module enumeration rejects non-table API results")
assert(tostring(modulesError):find("did not return a table", 1, true), "module failure explains the invalid result")

local function verifyModelRegressions(Model, label)
    local environment = { retained = true }
    local closureCalls = 0
    _G.getScriptClosure = function()
        closureCalls = closureCalls + 1
        return scriptClosure
    end
    _G.getSenv = function() return environment end
    _G.getMenv = nil
    _G.getConstants = function() return { [1] = false, [3] = "sparse constant" } end
    _G.getProtos = function() return { [3] = scriptClosure } end

    local seeded = Model.new({}, scriptClosure, environment)
    assertEqual(seeded:LoadClosure(), scriptClosure, label .. " preserves seeded closure")
    assertEqual(seeded:LoadEnvironment(), environment, label .. " preserves seeded environment")
    assertEqual(closureCalls, 0, label .. " seeded values do not trigger reads")
    local invalidSeed = Model.new({}, false, "invalid environment")
    assertEqual(invalidSeed:LoadClosure(), scriptClosure, label .. " validates seeded closure type")
    assertEqual(invalidSeed:LoadEnvironment(), environment, label .. " validates seeded environment type")
    assertEqual(invalidSeed:LoadConstants()[1], false, label .. " preserves false constants")
    assertEqual(invalidSeed.Constants[3], "sparse constant", label .. " preserves sparse constant indices")
    assertEqual(invalidSeed:LoadProtos()[3], scriptClosure, label .. " preserves proto indices")
    for public, exported in pairs({
        LoadClosure = "loadClosure", LoadEnvironment = "loadEnvironment", LoadConstants = "loadConstants",
        LoadProtos = "loadProtos", Decompile = "decompile", ClearFunctionSourceCache = "clearFunctionSourceCache"
    }) do
        assertEqual(invalidSeed[public], Model[exported], label .. " preserves " .. public .. " alias")
    end

    _G.decompile = function() return string.rep("x", 4096) end
    local refreshed = Model.new({})
    refreshed:Decompile(nil, 1024)
    local refreshCalls = 0
    _G.decompile = function()
        refreshCalls = refreshCalls + 1
        return nil, "decompiler unavailable"
    end
    local source, message = refreshed:Decompile(nil, 2048)
    assertEqual(source, nil, label .. " failed larger refresh returns no source")
    assertEqual(message, "decompiler unavailable", label .. " retains decompiler detail")
    assertEqual(refreshed.Source, nil, label .. " failed refresh clears stale source")
    assertEqual(refreshed:Decompile(nil, 4096), nil, label .. " cached failure does not resurrect old source")
    assertEqual(refreshCalls, 2, label .. " failed instance and closure results are cached")

    local target = function() end
    local errorCalls = 0
    _G.decompile = function()
        errorCalls = errorCalls + 1
        return nil, string.rep("error", 20000)
    end
    local failed = Model.new({})
    local _, boundedError = failed:Decompile(target, 1024)
    assert(#boundedError <= 2048, label .. " bounds retained decompiler errors")
    failed:Decompile(target, 4096)
    assertEqual(errorCalls, 1, label .. " does not retry a cached failure for a larger limit")
    _G.decompile = function()
        error(setmetatable({}, { __tostring = function() error("cannot format") end }), 0)
    end
    local _, unprintableError = Model.new({}):Decompile(target)
    assertEqual(unprintableError, "Unable to format inspector error", label .. " safely handles unprintable errors")

    _G.decompile = function() return string.rep("\226\130\172", 2000) end
    local unicodeSource = Model.new({}):Decompile(nil, 1024)
    assert(#unicodeSource <= 1024 and utf8.len(unicodeSource), label .. " truncates at a UTF-8 boundary")
    _G.oh = { Settings = { MaxInspectorBytes = 1024, MaxFunctionSourceCacheEntries = 0 / 0, MaxFunctionSourceCacheBytes = 0 / 0 } }
    _G.decompile = function() return string.rep("x", 4096) end
    assertEqual(#Model.new({}):Decompile(target, 0 / 0), 1024, label .. " NaN limits use configured defaults")
    _G.oh = nil

    local cleared = Model.new({})
    _G.decompile = function()
        cleared:ClearFunctionSourceCache()
        return "-- completed after cache clear"
    end
    assertEqual(cleared:Decompile(target), "-- completed after cache clear", label .. " returns completed work to its caller")
    assertEqual(cleared.FunctionSources[target], nil, label .. " late work does not repopulate a cleared cache")
    assertEqual(cleared.FunctionSourceBytes, 0, label .. " late work reserves no cache bytes")
    cleared.FunctionSourceOrder[1] = target
    cleared:ClearFunctionSourceCache()
    assertEqual(#cleared.FunctionSourceOrder, 0, label .. " clears stale order entries without looping")

    for _, functionTarget in ipairs({ false, true }) do
        local concurrent = Model.new({})
        local requestedTarget = functionTarget and target or nil
        local first = true
        _G.decompile = function()
            if first then
                first = false
                coroutine.yield()
            end
            return string.rep("s", 3000)
        end
        local pending = coroutine.create(function() return concurrent:Decompile(requestedTarget, 1024) end)
        assert(coroutine.resume(pending))
        concurrent:Decompile(requestedTarget, 4096)
        assert(coroutine.resume(pending))
        local retained = functionTarget and concurrent.FunctionSources[target].Source or concurrent.Source
        assertEqual(#retained, 3000, label .. " smaller late request cannot downgrade retained source")
    end

    local closed = Model.new({})
    _G.decompile = function()
        closed:Destroy()
        return "-- completed after close"
    end
    local closedSource, closedError = closed:Decompile(target)
    assertEqual(closedSource, nil, label .. " rejects results after destruction")
    assertEqual(closedError, "Script inspector has been closed", label .. " explains closed inspector")
    assertEqual(closed.Instance, nil, label .. " destruction releases instance")
    assertEqual(next(closed.FunctionSources), nil, label .. " destruction retains no function sources")
    closed:Destroy()
    assertEqual(closed:LoadClosure(), nil, label .. " destroyed model cannot reload resources")

    local closedEnvironment = Model.new({})
    _G.getSenv = function()
        closedEnvironment:Destroy()
        return environment
    end
    assertEqual(closedEnvironment:LoadEnvironment(), nil, label .. " rejects environment completing after close")
    assertEqual(closedEnvironment.Environment, nil, label .. " releases late environment result")
end

verifyModelRegressions(LocalScript, "local model")
verifyModelRegressions(ModuleScript, "module model")

local function newBudget()
    local budget = { Entries = 0, Tokens = {} }
    function budget:Reserve(_bytes, evict)
        local token = { Owner = self, Active = true, Evict = evict }
        self.Tokens[#self.Tokens + 1] = token
        self.Entries = self.Entries + 1
        return token
    end
    function budget:Release(token, evict)
        assertEqual(token.Owner, self, "cache token is released to its original owner")
        if token.Active then
            token.Active = false
            self.Entries = self.Entries - 1
            local callback = token.Evict
            token.Evict = nil
            if evict and callback then callback() end
        end
    end
    return budget
end

do
    local originalBudget, replacementBudget = newBudget(), newBudget()
    _G.oh = { Settings = {}, FunctionSourceCache = originalBudget }
    _G.decompile = function() return "-- retained source" end
    local first, second = LocalScript.new({}), ModuleScript.new({})
    local target = function() end
    first:Decompile(target)
    second:Decompile(target)
    oh.FunctionSourceCache = replacementBudget
    first:Destroy()
    assertEqual(originalBudget.Entries, 1, "destroy releases only its own model cache")
    assertEqual(second.FunctionSources[target].Source, "-- retained source", "neighboring model is preserved")
    second:ClearFunctionSourceCache()
    assertEqual(originalBudget.Entries, 0, "cleanup releases the reserving session budget")
    assertEqual(replacementBudget.Entries, 0, "cleanup does not alter a replacement session")

    local abandoned = LocalScript.new({})
    abandoned:Decompile(target)
    local weakOwner = setmetatable({ abandoned }, { __mode = "v" })
    abandoned = nil
    collectgarbage("collect")
    collectgarbage("collect")
    assertEqual(weakOwner[1], nil, "shared budget does not retain an abandoned model")
    replacementBudget:Release(replacementBudget.Tokens[1], true)
    _G.oh = nil
end

for _, Model in ipairs({ LocalScript, ModuleScript }) do
    local originalBudget, replacementBudget = newBudget(), newBudget()
    local originalRuntime = { Settings = { MaxInspectorBytes = 1024 }, FunctionSourceCache = originalBudget }
    local replacementRuntime = { Settings = { MaxInspectorBytes = 4096 }, FunctionSourceCache = replacementBudget }
    _G.oh = originalRuntime
    local model = Model.new({})
    _G.oh = replacementRuntime
    _G.decompile = function() return string.rep("x", 4096) end
    local target = function() end
    assertEqual(#model:Decompile(target), 1024, "model retains its owning runtime limits")
    assertEqual(originalBudget.Entries, 1, "model reserves only its owning runtime budget")
    assertEqual(replacementBudget.Entries, 0, "old model leaves replacement budget untouched")
    originalRuntime.Exited = true
    assertEqual(model:Decompile(target), nil, "cached values cannot reopen an exited session")
    assertEqual(originalBudget.Entries, 0, "closed owner releases model resources on access")

    originalRuntime.Exited = false
    _G.oh = originalRuntime
    local pendingModel = Model.new({})
    _G.decompile = function()
        coroutine.yield()
        return "-- decompiler completed after session exit"
    end
    local pendingResult
    local pending = coroutine.create(function() pendingResult = pendingModel:Decompile(target) end)
    assert(coroutine.resume(pending))
    originalRuntime.Exited = true
    _G.oh = replacementRuntime
    assert(coroutine.resume(pending))
    assertEqual(pendingResult, nil, "in-flight decompile is discarded after owner exits")
    assertEqual(pendingModel._Destroyed, true, "late access disposes an exited owner's model")
    assertEqual(originalBudget.Entries, 0, "late result does not reserve old budget")
    assertEqual(replacementBudget.Entries, 0, "late result does not reserve replacement budget")
    _G.oh = nil
end

do
    local cancelled = false
    _G.getLoadedModules = function()
        cancelled = true
        return manyModules
    end
    local delivered = 0
    local total, stopped = ModuleScanner.Enumerate("", function() delivered = delivered + 1 end, {
        IsCancelled = function() return cancelled end
    })
    assertEqual(total, 0, "cancelled provider result is discarded before rows are delivered")
    assertEqual(stopped, true, "provider-time cancellation is reported")
    assertEqual(delivered, 0, "cancelled provider does not invoke consumers")

    cancelled = false
    _G.getLoadedModules = function() return { manyModules[1] } end
    total, stopped = ModuleScanner.Enumerate("", function() cancelled = true end, {
        IsCancelled = function() return cancelled end
    })
    assertEqual(total, 1, "partial-batch cancellation preserves completed count")
    assertEqual(stopped, true, "cancellation in final partial batch is reported")

    local visits, waits = 0, 0
    _G.task = { wait = function() waits = waits + 1 end }
    local Scanner = import("modules/Scanner")
    local checkpoint = Scanner.checkpoint({ YieldEvery = 0 / 0 })
    for _ = 1, 128 do checkpoint() end
    assertEqual(waits, 1, "NaN scan intervals preserve default yielding")
    checkpoint = Scanner.checkpoint({ YieldEvery = math.huge })
    for _ = 1, 4096 do checkpoint() end
    assertEqual(waits, 2, "infinite scan intervals remain bounded")
    checkpoint = Scanner.checkpoint({ YieldEvery = 16, Yield = false, IsCancelled = function() return visits >= 16 end })
    assertEqual(checkpoint(true), false, "checkpoint supports a check without advancing work")
    for _ = 1, 16 do visits = visits + 1; stopped = checkpoint() end
    assertEqual(stopped, true, "non-yielding scans still honor cancellation")
    assertEqual(waits, 2, "Yield=false does not call task.wait")
    _G.task = nil
end

print("scanner_spec.lua: ok")
