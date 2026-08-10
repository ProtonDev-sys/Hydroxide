local root = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\][^/\\]+$")) or ""
assert(root, "unable to locate repository root")

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
    end
end

_G.typeof = _G.typeof or type
table.find = table.find or function(values, target)
    for index, value in ipairs(values) do
        if value == target then
            return index
        end
    end
end

local Remote = dofile(root .. "objects/Remote.lua")
local remote = Remote.new({}, 2)
local first = { id = 1 }
local second = { id = 2 }
local third = { id = 3 }

remote:IncrementCalls(first)
remote:IncrementCalls(second)
remote:IncrementCalls(third)

assertEqual(remote.TotalCalls, 3, "lifetime call count")
assertEqual(remote.Calls, 3, "call counter is independent of bounded retention")
assertEqual(remote.DroppedCalls, 1, "dropped call count")
assertEqual(#remote.Logs, 2, "bounded log count")
assertEqual(remote.Logs[1], second, "oldest log evicted")
assertEqual(remote.Logs[2], third, "newest log retained")

remote:BlockArg(2, "nil", true)
remote:IgnoreArg(3, "number", true)

local packedArguments = {
    n = 3,
    [1] = "first",
    [3] = 42
}

assertEqual(remote:AreArgsBlocked(packedArguments), true, "nil packed argument can be blocked by type")
assertEqual(remote:AreArgsIgnored(packedArguments), true, "argument after packed nil can be ignored")

remote:Clear()
assertEqual(remote.TotalCalls, 0, "clear resets total calls")
assertEqual(remote.DroppedCalls, 0, "clear resets dropped calls")
assertEqual(#remote.Logs, 0, "clear removes retained logs")

print("remote_spec.lua: ok")

do
    local originalCalls = 0
    local directWrappers = {}
    local namecallWrapper
    local currentNamecallMethod = "FireServer"
    local externalCaller = function() end
    local classMethods = {
        RemoteEvent = {},
        UnreliableRemoteEvent = {},
        RemoteFunction = {},
        BindableEvent = {},
        BindableFunction = {}
    }

    classMethods.RemoteEvent.FireServer = function()
        originalCalls = originalCalls + 1
        return "remote-event-result"
    end
    classMethods.UnreliableRemoteEvent.FireServer = function()
        originalCalls = originalCalls + 1
    end
    classMethods.RemoteFunction.InvokeServer = function()
        originalCalls = originalCalls + 1
        return "remote-function-result"
    end
    classMethods.BindableEvent.Fire = function(instance, ...)
        originalCalls = originalCalls + 1

        for _, callback in ipairs(instance._listeners) do
            callback(...)
        end
    end
    classMethods.BindableFunction.Invoke = function()
        originalCalls = originalCalls + 1
    end

    local function newInstance(className)
        local methods = assert(classMethods[className], "unexpected instance class " .. tostring(className))
        local instance = {
            __instance = true,
            ClassName = className,
            Name = className,
            _listeners = {}
        }

        instance.Event = {
            Connect = function(_, callback)
                instance._listeners[#instance._listeners + 1] = callback
                return {
                    Disconnect = function() end
                }
            end
        }

        return setmetatable(instance, {
            __index = function(_, key)
                if key == "Destroy" then
                    return function() end
                end

                return methods[key]
            end
        })
    end

    _G.typeof = function(value)
        if type(value) == "table" and value.__instance then
            return "Instance"
        end

        return type(value)
    end
    _G.Instance = {
        new = newInstance
    }
    _G.DateTime = {
        now = function()
            return {
                UnixTimestampMillis = 1234567890000
            }
        end
    }
    _G.oh = {
        Events = {},
        Hooks = {},
        Instances = {},
        Settings = {
            CaptureExecutorCalls = false,
            CaptureCallStacks = true,
            MaxRemoteLogs = 2
        }
    }
    _G.import = function(path)
        assertEqual(path, "objects/Remote", "RemoteSpy import")
        return Remote
    end
    _G.checkCaller = function()
        return false
    end
    _G.getCallingScript = function()
        return nil
    end
    _G.getInfo = function()
        return {
            func = classMethods.RemoteEvent.FireServer,
            name = "caller",
            source = "remote_spec.lua",
            currentline = 1
        }
    end
    _G.getCallStack = function(offset)
        assertEqual(offset, 0, "Potassium call stack offset")
        return {
            {
                func = function() end,
                name = "RemoteSpyInternal",
                source = "@modules/RemoteSpy.lua",
                currentline = 200
            },
            {
                func = externalCaller,
                name = "ExternalCaller",
                source = "@game/ExternalCaller.lua",
                currentline = 42
            }
        }
    end
    _G.getNamecallMethod = function()
        return currentNamecallMethod
    end
    _G.newCClosure = nil
    local othHookCalls = 0
    _G.othHook = function()
        othHookCalls = othHookCalls + 1
        return false
    end
    _G.othGetRootCallback = function()
        error("an explicitly failed OTH hook must never run")
    end
    _G.othUnhook = function() end
    _G.hookFunction = function(target, wrapper)
        directWrappers[target] = wrapper
        return target
    end

    local gameObject = {}
    local function originalNamecall(instance, ...)
        local target = instance[currentNamecallMethod]
        return (directWrappers[target] or target)(instance, ...)
    end

    _G.game = gameObject
    _G.getMetatable = function()
        return {
            __namecall = originalNamecall
        }
    end
    _G.hookMetaMethod = function(object, method, wrapper)
        assertEqual(object, gameObject, "namecall hook object")
        assertEqual(method, "__namecall", "namecall hook method")
        namecallWrapper = wrapper
        return originalNamecall
    end

    local RemoteSpy = dofile(root .. "modules/RemoteSpy.lua")
    assertEqual(RemoteSpy.RemotesViewing.RemoteFunction, true, "RemoteFunction enabled by default")
    assertEqual(RemoteSpy.Diagnostics.NamecallHookInstalled, true, "namecall hook always installed")
    assertEqual(RemoteSpy.Diagnostics.DirectHooksInstalled, 5, "original-thread function hooks installed")
    assertEqual(RemoteSpy.Diagnostics.DirectHookFailures, 0, "successful function hooks do not report failures")
    assertEqual(othHookCalls, 0, "off-thread hooks are reserved for fallback")

    local event = newInstance("RemoteEvent")
    local result = namecallWrapper(event, "first", nil, "third")
    local eventModel = RemoteSpy.CurrentRemotes[event]

    assertEqual(result, "remote-event-result", "namecall preserves original result")
    assertEqual(eventModel.TotalCalls, 1, "call retained before UI subscription")
    assertEqual(eventModel.Logs[1].args.n, 3, "captured arguments retain packed length")
    assertEqual(eventModel.Logs[1].args[3], "third", "captured argument after nil retained")
    assertEqual(eventModel.Logs[1].func, externalCaller, "first external stack frame selected as caller")
    assertEqual(eventModel.Logs[1].caller.name, "ExternalCaller", "external caller name retained")
    assertEqual(eventModel.Logs[1].caller.source, "@game/ExternalCaller.lua", "external caller source retained")
    assertEqual(eventModel.Logs[1].caller.line, 42, "external caller line retained")
    assertEqual(#eventModel.Logs[1].stack, 1, "internal RemoteSpy stack frames filtered")
    assertEqual(RemoteSpy.Diagnostics.CallsDeduplicated, 1, "direct/namecall pair deduplicated")

    local executorEvent = newInstance("RemoteEvent")
    _G.checkCaller = function()
        return true
    end
    local callsBeforeExecutor = originalCalls
    directWrappers[classMethods.RemoteEvent.FireServer](executorEvent, "executor")
    assertEqual(originalCalls, callsBeforeExecutor + 1, "executor filtering does not block the original call")
    assertEqual(RemoteSpy.CurrentRemotes[executorEvent], nil, "executor call is not captured when filtering")
    assertEqual(RemoteSpy.Diagnostics.ExecutorCallsSkipped, 1, "executor skip diagnosed")

    local unknownCallerEvent = newInstance("RemoteEvent")
    _G.checkCaller = nil
    local callsBeforeUnknownCaller = originalCalls
    directWrappers[classMethods.RemoteEvent.FireServer](unknownCallerEvent, "unknown-caller")
    assertEqual(originalCalls, callsBeforeUnknownCaller + 1, "unknown caller filtering remains fail-open")
    assertEqual(RemoteSpy.CurrentRemotes[unknownCallerEvent], nil, "unknown caller is not captured when filtering")
    assertEqual(RemoteSpy.Diagnostics.CallsSkippedUnknownCaller, 1, "unknown caller skip diagnosed")
    _G.checkCaller = function()
        return false
    end

    local callsBeforeCaptureError = originalCalls
    eventModel.IgnoredArgs[1] = {
        types = {},
        values = {}
    }
    local originalAreArgsIgnored = eventModel.AreArgsIgnored
    eventModel.AreArgsIgnored = function()
        error("capture failure")
    end
    directWrappers[classMethods.RemoteEvent.FireServer](event, "capture-error")
    assertEqual(originalCalls, callsBeforeCaptureError + 1, "capture failure is fail-open")
    assertEqual(RemoteSpy.Diagnostics.CaptureErrors > 0, true, "capture failure diagnosed")
    eventModel.AreArgsIgnored = originalAreArgsIgnored
    eventModel.IgnoredArgs = {}

    eventModel:SetBlocked(true)
    local callsBeforeBlock = originalCalls
    directWrappers[classMethods.RemoteEvent.FireServer](event, "blocked")
    assertEqual(originalCalls, callsBeforeBlock, "blocked call does not reach original")

    eventModel:SetBlocked(false)
    directWrappers[classMethods.RemoteEvent.FireServer](event, "retained")
    assertEqual(#eventModel.Logs, 2, "RemoteSpy applies configured retention bound")
    assertEqual(RemoteSpy.Diagnostics.LogsDropped, 1, "retention eviction diagnosed")

    currentNamecallMethod = "InvokeServer"
    local remoteFunction = newInstance("RemoteFunction")
    local invokeResult = namecallWrapper(remoteFunction, "request")
    assertEqual(invokeResult, "remote-function-result", "RemoteFunction result preserved")
    assertEqual(RemoteSpy.CurrentRemotes[remoteFunction].TotalCalls, 1, "RemoteFunction captured")

    print("remote_spy backend: ok")
end
