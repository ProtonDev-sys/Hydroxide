local RemoteSpy = {}
local Remote = import("objects/Remote")

local requiredMethods = {
    ["checkCaller"] = true,
    ["getInfo"] = true,
    ["getMetatable"] = true,
    ["setClipboard"] = true,
    ["getCallingScript"] = true
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

local function normalizeMethod(method)
    if method == "fireServer" then
        return "FireServer"
    elseif method == "invokeServer" then
        return "InvokeServer"
    elseif method == "fire" then
        return "Fire"
    elseif method == "invoke" then
        return "Invoke"
    end

    return method
end

local function connectEvent(callback)
    remoteDataEvent.Event:Connect(callback)

    if not eventSet then
        eventSet = true
    end
end

local function ensureRemote(instance)
    local remote = currentRemotes[instance]

    if not remote then
        remote = Remote.new(instance)
        currentRemotes[instance] = remote
    end

    return remote
end

local function buildCall(stackLevel, vargs)
    local info = getInfo and getInfo(stackLevel)

    return {
        script = getCallingScript((PROTOSMASHER_LOADED ~= nil and stackLevel - 1) or nil),
        args = vargs,
        func = info and info.func
    }
end

local function processRemoteCall(instance, method, stackLevel, vargs)
    if typeof(instance) ~= "Instance" then
        return false
    end

    method = normalizeMethod(method)

    if not remotesViewing[instance.ClassName] or instance == remoteDataEvent or not remoteMethods[method] then
        return false
    end

    local remote = ensureRemote(instance)
    local remoteIgnored = remote.Ignored
    local remoteBlocked = remote.Blocked
    local argsIgnored = remote:AreArgsIgnored(vargs)
    local argsBlocked = remote:AreArgsBlocked(vargs)

    if eventSet and not remoteIgnored and not argsIgnored then
        local call = buildCall(stackLevel, vargs)

        remote:IncrementCalls(call)
        remoteDataEvent:Fire(instance, call)
    end

    return remoteBlocked or argsBlocked
end

local function createHookCallback(target, targetMethod)
    return function(original, ...)
        local instance = ...

        if typeof(instance) ~= "Instance" then
            return original(...)
        end

        local blocked = processRemoteCall(instance, targetMethod, 3, { select(2, ...) })

        if blocked then
            return
        end

        return original(...)
    end
end

local function installDirectHook(target, callback)
    if othHook and othGetRootCallback then
        local handle
        local ran = pcall(function()
            handle = othHook(target, function(...)
                local original = othGetRootCallback() or target
                return callback(original, ...)
            end)
        end)

        if ran and handle then
            table.insert(oh.Hooks, {
                Kind = "oth",
                Handle = handle
            })

            return true
        end
    end

    if not hookFunction then
        return false
    end

    local original
    local wrapper = newCClosure and newCClosure(function(...)
        return callback(original, ...)
    end) or function(...)
        return callback(original, ...)
    end

    original = hookFunction(target, wrapper)
    table.insert(oh.Hooks, {
        Kind = "function",
        Target = target,
        Original = original
    })

    return true
end

local function createHookTarget(className, methodName)
    local ran, instance = pcall(Instance.new, className)

    if not ran or not instance then
        return nil
    end

    local target = instance[methodName]

    pcall(function()
        instance:Destroy()
    end)

    return target
end

local installedDirectHook = false
local directTargets = {
    { "RemoteEvent", "FireServer" },
    { "UnreliableRemoteEvent", "FireServer" },
    { "RemoteFunction", "InvokeServer" },
    { "BindableEvent", "Fire" },
    { "BindableFunction", "Invoke" }
}

for _, hookInfo in ipairs(directTargets) do
    local className = hookInfo[1]
    local methodName = hookInfo[2]
    local target = createHookTarget(className, methodName)

    if target then
        local callback = createHookCallback(target, methodName)

        if installDirectHook(target, callback) then
            installedDirectHook = true
        end
    end
end

if not installedDirectHook and hookMetaMethod and getNamecallMethod then
    local originalNamecall

    originalNamecall = hookMetaMethod(game, "__namecall", function(...)
        local instance = ...

        if typeof(instance) ~= "Instance" then
            return originalNamecall(...)
        end

        local blocked = processRemoteCall(instance, getNamecallMethod(), 3, { select(2, ...) })

        if blocked then
            return
        end

        return originalNamecall(...)
    end)
end

RemoteSpy.RemotesViewing = remotesViewing
RemoteSpy.CurrentRemotes = currentRemotes
RemoteSpy.ConnectEvent = connectEvent
RemoteSpy.RequiredMethods = requiredMethods
RemoteSpy.IsSupported = installedDirectHook or (hookMetaMethod and getNamecallMethod) or false
return RemoteSpy
