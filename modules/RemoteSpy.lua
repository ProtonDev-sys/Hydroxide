local RemoteSpy = {}
local Remote = import("objects/Remote")

local requiredMethods = {
    ["getInfo"] = true,
    ["setClipboard"] = true
}

local remoteMethods = {
    FireServer = true,
    InvokeServer = true,
    Fire = true,
    Invoke = true
}

local remotesViewing = {
    RemoteEvent = true,
    UnreliableRemoteEvent = true,
    RemoteFunction = false,
    BindableEvent = false,
    BindableFunction = false
}

local currentRemotes = {}
local remoteDataEvent = Instance.new("BindableEvent")
local eventSet = false

oh.Instances[#oh.Instances + 1] = remoteDataEvent

local function normalizeMethod(method)
    if type(method) ~= "string" then
        return method
    end

    local lowered = method:lower()

    if lowered == "fireserver" then
        return "FireServer"
    elseif lowered == "invokeserver" then
        return "InvokeServer"
    elseif lowered == "fire" then
        return "Fire"
    elseif lowered == "invoke" then
        return "Invoke"
    end

    return method
end

local function connectEvent(callback)
    local connection = remoteDataEvent.Event:Connect(callback)

    oh.Events[#oh.Events + 1] = connection
    eventSet = true
    return connection
end

local function ensureRemote(instance)
    local remote = currentRemotes[instance]

    if not remote then
        remote = Remote.new(instance)
        currentRemotes[instance] = remote
    end

    return remote
end

local function safeCheckCaller()
    if not checkCaller then
        return false
    end

    return checkCaller() == true
end

local function safeCallingScript()
    if not getCallingScript then
        return nil
    end

    local ran, result = pcall(getCallingScript)
    return ran and result or nil
end

local function callingScriptFromOriginalThread()
    if not (othGetOriginalThread and getScriptFromThread) then
        return nil
    end

    local threadRan, originalThread = pcall(othGetOriginalThread)

    if not threadRan or not originalThread then
        return nil
    end

    local scriptRan, script = pcall(getScriptFromThread, originalThread)
    return scriptRan and script or nil
end

local function buildCall(stackLevel, vargs, callingScript, callingScriptResolved)
    local info
    local script = callingScript

    if getInfo then
        local ran, result = pcall(getInfo, stackLevel, "f")
        info = ran and result or nil
    end

    if not callingScriptResolved then
        script = safeCallingScript()
    end

    return {
        script = script,
        args = vargs,
        func = info and info.func
    }
end

local function processRemoteCall(instance, method, stackLevel, vargs, callingScript, callingScriptResolved)
    if typeof(instance) ~= "Instance" or (not callingScriptResolved and safeCheckCaller()) then
        return false
    end

    method = normalizeMethod(method)

    if not remotesViewing[instance.ClassName] or instance == remoteDataEvent or not remoteMethods[method] then
        return false
    end

    local remote = ensureRemote(instance)
    local argsIgnored = next(remote.IgnoredArgs) ~= nil and remote:AreArgsIgnored(vargs)
    local argsBlocked = next(remote.BlockedArgs) ~= nil and remote:AreArgsBlocked(vargs)

    if eventSet and not remote.Ignored and not argsIgnored then
        local call = buildCall(stackLevel, vargs, callingScript, callingScriptResolved)

        remote:IncrementCalls(call)
        remoteDataEvent:Fire(instance, call)
    end

    return remote.Blocked or argsBlocked
end

local function createHookCallback(targetMethod)
    return function(original, callingScript, callingScriptResolved, ...)
        local instance = ...

        if typeof(instance) ~= "Instance" then
            return original(...)
        end

        local blocked = processRemoteCall(
            instance,
            targetMethod,
            3,
            { select(2, ...) },
            callingScript,
            callingScriptResolved
        )

        if blocked then
            return
        end

        return original(...)
    end
end

local function installDirectHook(target, callback)
    if othHook and othGetRootCallback and othUnhook then
        local ran = pcall(othHook, target, function(...)
            local original = othGetRootCallback()

            if not original then
                return
            end

            return callback(original, callingScriptFromOriginalThread(), true, ...)
        end)

        if ran then
            oh.Hooks[#oh.Hooks + 1] = {
                Kind = "oth",
                Target = target,
                Active = true
            }

            return true
        end
    end

    if not hookFunction then
        return false
    end

    local original
    local callbackWrapper = function(...)
        return callback(original, nil, false, ...)
    end
    local wrapper = newCClosure and newCClosure(callbackWrapper) or callbackWrapper
    local ran, result = pcall(hookFunction, target, wrapper)

    if not ran or type(result) ~= "function" then
        return false
    end

    original = result
    oh.Hooks[#oh.Hooks + 1] = {
        Kind = "function",
        Target = target,
        Original = original,
        Active = true
    }

    return true
end

local function createHookTarget(className, methodName)
    local ran, instance = pcall(Instance.new, className)

    if not ran or not instance then
        return nil
    end

    local targetRan, target = pcall(function()
        return instance[methodName]
    end)

    pcall(function()
        instance:Destroy()
    end)

    return targetRan and target or nil
end

local directTargets = {
    { "RemoteEvent", "FireServer" },
    { "UnreliableRemoteEvent", "FireServer" },
    { "RemoteFunction", "InvokeServer" },
    { "BindableEvent", "Fire" },
    { "BindableFunction", "Invoke" }
}
local targetGroups = {}
local directHookedClasses = {}
local installedDirectHook = false

for _, hookInfo in ipairs(directTargets) do
    local className = hookInfo[1]
    local methodName = hookInfo[2]
    local target = createHookTarget(className, methodName)

    if target then
        local group = targetGroups[target]

        if not group then
            group = {
                Method = methodName,
                Classes = {}
            }
            targetGroups[target] = group
        end

        group.Classes[className] = true
    end
end

for target, group in pairs(targetGroups) do
    if installDirectHook(target, createHookCallback(group.Method)) then
        installedDirectHook = true

        for className in pairs(group.Classes) do
            directHookedClasses[className] = true
        end
    end
end

local needsNamecallFallback = false

for _, hookInfo in ipairs(directTargets) do
    if not directHookedClasses[hookInfo[1]] then
        needsNamecallFallback = true
        break
    end
end

local installedNamecallHook = false

if needsNamecallFallback and hookMetaMethod and getNamecallMethod then
    local metatable = getMetatable and getMetatable(game)
    local target = metatable and metatable.__namecall
    local originalNamecall
    local callback = function(...)
        local instance = ...

        if typeof(instance) ~= "Instance" or directHookedClasses[instance.ClassName] then
            return originalNamecall(...)
        end

        local blocked = processRemoteCall(instance, getNamecallMethod(), 3, { select(2, ...) })

        if blocked then
            return
        end

        return originalNamecall(...)
    end
    local wrapper = newCClosure and newCClosure(callback) or callback
    local ran, original = pcall(hookMetaMethod, game, "__namecall", wrapper)

    if ran and type(original) == "function" then
        originalNamecall = original
        installedNamecallHook = true
        oh.Hooks[#oh.Hooks + 1] = {
            Kind = "metamethod",
            Target = target,
            Object = game,
            Method = "__namecall",
            Original = original,
            Active = true
        }
    end
end

RemoteSpy.RemotesViewing = remotesViewing
RemoteSpy.CurrentRemotes = currentRemotes
RemoteSpy.ConnectEvent = connectEvent
RemoteSpy.RequiredMethods = requiredMethods
RemoteSpy.IsSupported = installedDirectHook or installedNamecallHook
return RemoteSpy
