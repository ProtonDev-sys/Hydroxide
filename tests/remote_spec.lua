local root = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\][^/\\]+$")) or ""
assert(root, "unable to locate repository root")

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
    end
end

local fakeBuffer = {}

function fakeBuffer.fromstring(bytes)
    return { __type = "buffer", bytes = bytes }
end

function fakeBuffer.tostring(value)
    return value.bytes
end

function fakeBuffer.len(value)
    return #value.bytes
end

function fakeBuffer.readu8(value, offset)
    return assert(value.bytes:byte(offset + 1))
end

_G.buffer = fakeBuffer
_G.typeof = function(value)
    return type(value) == "table" and value.__type or type(value)
end
table.find = table.find or function(values, target)
    for index, value in ipairs(values) do
        if value == target then
            return index
        end
    end
end

local packValues = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack

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

local byteBoundRemote = Remote.new({}, 10, 3)
byteBoundRemote:IncrementCalls({ id = "A", capturedBytes = 2 })
byteBoundRemote:IncrementCalls({ id = "B", capturedBytes = 2 })
assertEqual(#byteBoundRemote.Logs, 1, "remote history byte budget evicts the oldest call")
assertEqual(byteBoundRemote.Logs[1].id, "B", "remote history byte budget retains the newest call")
assertEqual(byteBoundRemote.HistoryBytes, 2, "remote history byte accounting is bounded")

remote:DecrementCalls(second)
assertEqual(#remote.Logs, 1, "circular history removes a logical entry")
assertEqual(remote.Logs[1], third, "circular history preserves order after removal")
assertEqual(remote.Calls, 2, "removing a retained call decrements the visible call count")

remote:BlockArg(2, "nil", true)
remote:IgnoreArg(3, "number", true)

local packedArguments = {
    n = 3,
    [1] = "first",
    [3] = 42
}

assertEqual(remote:AreArgsBlocked(packedArguments), true, "nil packed argument can be blocked by type")
assertEqual(remote:AreArgsIgnored(packedArguments), true, "argument after packed nil can be ignored")

local conditionRemote = Remote.new({}, 2)
assertEqual(conditionRemote:BlockArg(1, nil, false), true, "exact nil normalizes to a nil type condition")
assertEqual(conditionRemote:BlockArg(2, 0 / 0, false), true, "NaN condition is stored without a table-key crash")
local expectedBuffer = fakeBuffer.fromstring("A\0B")
local matchingBuffer = fakeBuffer.fromstring("A\0B")
assertEqual(conditionRemote:BlockArg(3, expectedBuffer, false), true, "buffer value condition added")
assertEqual(conditionRemote:BlockArg(3, expectedBuffer, false), false, "duplicate condition rejected")
assertEqual(conditionRemote:BlockArg(0, "string", true), false, "invalid condition index rejected")
assertEqual(conditionRemote:AreArgsBlocked({ n = 1 }), true, "exact nil condition matches packed nil")
assertEqual(conditionRemote:AreArgsBlocked({ n = 2, [1] = true, [2] = 0 / 0 }), true, "NaN condition matches")
assertEqual(
    conditionRemote:AreArgsBlocked({ n = 3, [1] = true, [2] = 2, [3] = matchingBuffer }),
    true,
    "equivalent buffer contents match without identity"
)

remote:Clear()
assertEqual(remote.TotalCalls, 0, "clear resets total calls")
assertEqual(remote.DroppedCalls, 0, "clear resets dropped calls")
assertEqual(#remote.Logs, 0, "clear removes retained logs")

print("remote_spec.lua: ok")

do
    local originalCalls = 0
    local directWrappers = {}
    local currentRootCallback
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
            _listeners = {},
            _destroyListeners = {}
        }

        instance.Event = {
            Connect = function(_, callback)
                instance._listeners[#instance._listeners + 1] = callback
                return {
                    Disconnect = function() end
                }
            end
        }
        instance.Destroying = {
            Connect = function(_, callback)
                instance._destroyListeners[#instance._destroyListeners + 1] = callback
                return {
                    Disconnect = function() end
                }
            end
        }

        return setmetatable(instance, {
            __index = function(_, key)
                if key == "Destroy" then
                    return function()
                        for _, callback in ipairs(instance._destroyListeners) do
                            callback()
                        end

                        instance._destroyListeners = {}
                    end
                end

                return methods[key]
            end
        })
    end

    _G.typeof = function(value)
        if type(value) == "table" and value.__instance then
            return "Instance"
        elseif type(value) == "table" and value.__type then
            return value.__type
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
            MaxStackCapturesPerSecond = 1,
            MaxRemoteLogs = 2,
            MaxGeneratedBufferBytes = 64,
            MaxGeneratedTableEntries = 32,
            MaxGeneratedTableDepth = 8,
            MaxHexBytes = 4,
            MaxCapturedCallBytes = 4096,
            MaxCapturedArguments = 128,
            MaxRemoteHistoryBytes = 65536
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
                name = "getcallstack",
                source = "=[C]",
                line = -1
            },
            {
                name = "pcall",
                source = "=[C]",
                line = -1
            },
            {
                func = function() end,
                name = "RemoteSpyInternal",
                source = "@modules/RemoteSpy.lua",
                currentline = 200
            },
            {
                func = externalCaller,
                name = "<anonymous>",
                source = "=ReplicatedStorage.Modules.EventManagerClient",
                currentline = 10
            },
            {
                func = function() end,
                name = "<anonymous>",
                source = "=Players.PlayerScripts.Gameplay.C_LootDropHandler",
                currentline = 337
            }
        }
    end
    _G.getNamecallMethod = function()
        return currentNamecallMethod
    end
    _G.newCClosure = nil
    local othHookCalls = 0
    _G.othHook = function(target, wrapper)
        othHookCalls = othHookCalls + 1
        directWrappers[target] = function(...)
            currentRootCallback = target
            local results = packValues(pcall(wrapper, ...))
            currentRootCallback = nil

            if not results[1] then
                error(results[2], 0)
            end

            return unpackValues(results, 2, results.n)
        end
        return target
    end
    local failRootLookup = false
    _G.othGetRootCallback = function()
        if failRootLookup then
            error("simulated root lookup failure")
        end

        return currentRootCallback
    end
    _G.othGetOriginalThread = coroutine.running
    _G.othUnhook = function() end
    local hookFunctionCalls = 0
    _G.hookFunction = function(target, wrapper)
        hookFunctionCalls = hookFunctionCalls + 1
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
    assertEqual(RemoteSpy.Diagnostics.DirectHooksInstalled, 5, "off-thread C-function hooks installed")
    assertEqual(RemoteSpy.Diagnostics.DirectHookFailures, 0, "successful direct hooks do not report failures")
    assertEqual(othHookCalls, 5, "Potassium OTH is preferred for C-function pass-through")
    assertEqual(hookFunctionCalls, 0, "hookfunction remains a fallback when OTH succeeds")

    local event = newInstance("RemoteEvent")
    local result = namecallWrapper(event, "first", nil, "third")
    local eventModel = RemoteSpy.CurrentRemotes[event]

    assertEqual(result, "remote-event-result", "namecall preserves original result")
    assertEqual(eventModel.TotalCalls, 1, "call retained before UI subscription")
    assertEqual(eventModel.Logs[1].args.n, 3, "captured arguments retain packed length")
    assertEqual(eventModel.Logs[1].args[3], "third", "captured argument after nil retained")
    assertEqual(eventModel.Logs[1].func, externalCaller, "first external stack frame selected as caller")
    assertEqual(eventModel.Logs[1].caller.name, "EventManagerClient", "anonymous caller gets a useful name")
    assertEqual(
        eventModel.Logs[1].caller.source,
        "ReplicatedStorage.Modules.EventManagerClient",
        "caller source normalized"
    )
    assertEqual(eventModel.Logs[1].caller.line, 10, "external caller line retained")
    assertEqual(eventModel.Logs[1].completed, true, "forwarded call is marked complete")
    assertEqual(eventModel.Logs[1].forwarded, true, "forwarded call is marked forwarded")
    assertEqual(eventModel.Logs[1].returns[1], "remote-event-result", "forwarded return value retained")
    assertEqual(#eventModel.Logs[1].stack, 2, "native and internal RemoteSpy stack frames filtered")
    assertEqual(eventModel.Logs[1].stack[2].name, "C_LootDropHandler", "anonymous parent frame gets a useful name")
    assertEqual(RemoteSpy.Diagnostics.CallsDeduplicated, 1, "direct/namecall pair deduplicated")

    local bufferEvent = newInstance("RemoteEvent")
    local sourceBuffer = fakeBuffer.fromstring("A\0B")
    namecallWrapper(bufferEvent, sourceBuffer, { nested = sourceBuffer })
    local bufferCall = RemoteSpy.CurrentRemotes[bufferEvent].Logs[1]
    sourceBuffer.bytes = "mutated"
    assertEqual(fakeBuffer.tostring(bufferCall.args[1]), "A\0B", "top-level buffer snapshot is immutable")
    assertEqual(fakeBuffer.tostring(bufferCall.args[2].nested), "A\0B", "nested buffer snapshot is immutable")
    assertEqual(bufferCall.replayable, true, "complete buffer snapshots remain replayable")

    local aggregateEvent = newInstance("RemoteEvent")
    local aggregateArgs = {}

    for index = 1, 65 do
        aggregateArgs[index] = fakeBuffer.fromstring(string.rep("x", 64))
    end

    namecallWrapper(aggregateEvent, unpackValues(aggregateArgs, 1, #aggregateArgs))
    local aggregateCall = RemoteSpy.CurrentRemotes[aggregateEvent].Logs[1]
    assertEqual(aggregateCall.replayable, false, "aggregate call byte overflow disables replay")
    assertEqual(aggregateCall.args[65].__hydroxideCaptureMarker, true, "overflowing buffer becomes a marker")
    assertEqual(aggregateCall.capturedBytes <= 4096, true, "aggregate captured bytes remain bounded")

    local invalidSnapshotEvent = newInstance("RemoteEvent")
    local originalFromString = fakeBuffer.fromstring
    fakeBuffer.fromstring = function()
        return nil
    end
    namecallWrapper(invalidSnapshotEvent, { __type = "buffer", bytes = "valid" })
    fakeBuffer.fromstring = originalFromString
    local invalidSnapshotCall = RemoteSpy.CurrentRemotes[invalidSnapshotEvent].Logs[1]
    assertEqual(invalidSnapshotCall.replayable, false, "invalid buffer snapshot disables replay")
    assertEqual(
        invalidSnapshotCall.args[1].__hydroxideCaptureMarker,
        true,
        "invalid buffer.fromstring result becomes an explicit marker"
    )

    local oversizedEvent = newInstance("RemoteEvent")
    namecallWrapper(oversizedEvent, fakeBuffer.fromstring(string.rep("x", 257)))
    local oversizedCall = RemoteSpy.CurrentRemotes[oversizedEvent].Logs[1]
    assertEqual(oversizedCall.replayable, false, "oversized buffer disables unsafe replay")
    assertEqual(oversizedCall.args[1].__hydroxideCaptureMarker, true, "oversized buffer becomes an explicit marker")
    assertEqual(oversizedCall.args[1].Size, 257, "oversized buffer marker retains original size")

    local fallbackEvent = newInstance("RemoteEvent")
    local callsBeforeRootFallback = originalCalls
    failRootLookup = true
    local fallbackResult = directWrappers[classMethods.RemoteEvent.FireServer](fallbackEvent, "root-fallback")
    failRootLookup = false
    assertEqual(fallbackResult, "remote-event-result", "OTH returned-original fallback preserves the call result")
    assertEqual(originalCalls, callsBeforeRootFallback + 1, "OTH root lookup failure still reaches the original")

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
    namecallWrapper(event, "capture-error")
    assertEqual(originalCalls, callsBeforeCaptureError + 1, "capture failure is fail-open")
    assertEqual(RemoteSpy.Diagnostics.CaptureErrors > 0, true, "capture failure diagnosed")
    eventModel.AreArgsIgnored = originalAreArgsIgnored
    eventModel.IgnoredArgs = {}

    eventModel:SetBlocked(true)
    local callsBeforeBlock = originalCalls
    namecallWrapper(event, "blocked")
    local blockedCall = eventModel.Logs[#eventModel.Logs]
    assertEqual(originalCalls, callsBeforeBlock, "blocked call does not reach original")
    assertEqual(blockedCall.blocked, true, "blocked call is marked blocked")
    assertEqual(blockedCall.forwarded, false, "blocked call is not marked forwarded")

    eventModel:SetBlocked(false)
    namecallWrapper(event, "retained")
    assertEqual(#eventModel.Logs, 2, "RemoteSpy applies configured retention bound")
    assertEqual(RemoteSpy.Diagnostics.LogsDropped, 1, "retention eviction diagnosed")
    assertEqual(RemoteSpy.Diagnostics.StackCapturesRateLimited > 0, true, "remote stack capture budget is enforced")

    currentNamecallMethod = "InvokeServer"
    local remoteFunction = newInstance("RemoteFunction")
    local invokeResult = namecallWrapper(remoteFunction, "request")
    assertEqual(invokeResult, "remote-function-result", "RemoteFunction result preserved")
    assertEqual(RemoteSpy.CurrentRemotes[remoteFunction].TotalCalls, 1, "RemoteFunction captured")

    event:Destroy()
    assertEqual(RemoteSpy.CurrentRemotes[event], nil, "destroyed remotes are released from backend history")
    assertEqual(RemoteSpy.Diagnostics.RemotesDisposed, 1, "destroyed remote cleanup is diagnosed")

    print("remote_spy backend: ok")
end
