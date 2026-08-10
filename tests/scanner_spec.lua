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

local LocalScript = dofile(root .. "objects/LocalScript.lua")
local ModuleScript = dofile(root .. "objects/ModuleScript.lua")
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
assertEqual(closureLoads, 1, "ModuleScript never passed to BaseScript-only getScriptClosure")

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
    return { runningLocal, runningScript, loadedModule }
end
_G.getLoadedModules = function()
    return { loadedModule, runningLocal }
end
_G.getScripts = function()
    error("getscripts must not change running/loaded scanner semantics")
end
_G.import = function(path)
    if path == "objects/LocalScript" then
        return LocalScript
    elseif path == "objects/ModuleScript" then
        return ModuleScript
    end

    error("unexpected import: " .. tostring(path))
end

local ScriptScanner = dofile(root .. "modules/ScriptScanner.lua")
local ModuleScanner = dofile(root .. "modules/ModuleScanner.lua")
local scriptResults = ScriptScanner.Scan("running")
local moduleResults = ModuleScanner.Scan("loaded")

assertEqual(scriptResults[runningLocal].Instance, runningLocal, "running LocalScript enumerated")
assertEqual(scriptResults[runningScript].Instance, runningScript, "running client-context Script enumerated")
assertEqual(scriptResults[loadedModule], nil, "ModuleScript excluded from ScriptScanner")
assertEqual(moduleResults[loadedModule].Instance, loadedModule, "loaded ModuleScript enumerated")
assertEqual(moduleResults[runningLocal], nil, "LocalScript excluded from ModuleScanner")

print("scanner_spec.lua: ok")
