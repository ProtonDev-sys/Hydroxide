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
    return { scriptValue = true }
end
_G.decompile = function(target)
    if target == scriptClosure then
        return "-- closure source"
    end

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
assertEqual(localModel:Decompile(), "-- instance source", "local instance decompile preferred")
assertEqual(localModel:Decompile(scriptClosure), "-- closure source", "local function decompile")

assertEqual(moduleModel:Decompile(), "-- instance source", "module instance decompile preferred")
assertEqual(closureLoads, 1, "ModuleScript never passed to BaseScript-only getScriptClosure")

local function makeScript(className, name)
    local instance = {
        __instance = true,
        ClassName = className,
        Name = name
    }

    function instance:IsA(targetClass)
        return self.ClassName == targetClass
    end

    return instance
end

_G.typeof = function(value)
    return type(value) == "table" and value.__instance and "Instance" or type(value)
end

local runningLocal = makeScript("LocalScript", "RunningClient")
local loadedModule = makeScript("ModuleScript", "LoadedModule")
_G.getRunningScripts = function()
    return { runningLocal, loadedModule }
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
assertEqual(scriptResults[loadedModule], nil, "ModuleScript excluded from ScriptScanner")
assertEqual(moduleResults[loadedModule].Instance, loadedModule, "loaded ModuleScript enumerated")
assertEqual(moduleResults[runningLocal], nil, "LocalScript excluded from ModuleScanner")

print("scanner_spec.lua: ok")
