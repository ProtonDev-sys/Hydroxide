local root = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\][^/\\]+$")) or ""
assert(root, "unable to locate repository root")

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
    end
end

table.find = table.find or function(values, target)
    for index, value in ipairs(values) do
        if value == target then
            return index
        end
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

local packValues = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack

_G.buffer = fakeBuffer
_G.typeof = function(value)
    return type(value) == "table" and value.__type or type(value)
end
_G.DateTime = {
    now = function()
        return { UnixTimestampMillis = 1700000000123 }
    end
}

local wrappers = {}
local originalCalls = 0
local externalCaller = function() end
local lastFirstArgument
local lastSecondArgument
local lastArgumentCount
local target = function(...)
    originalCalls = originalCalls + 1
    lastFirstArgument = select(1, ...)
    lastSecondArgument = select(2, ...)
    lastArgumentCount = select("#", ...)

    if select(1, ...) == "explode" then
        error("target exploded")
    elseif select(1, ...) == "mutate-argument" then
        local value = select(2, ...)
        value.changedByTarget = true
        return value, nil, select("#", ...)
    elseif select(1, ...) == "return-many" then
        return select(2, ...), nil, 3, 4, 5, 6, 7, 8, 9
    end

    return "result", nil, select("#", ...)
end

_G.oh = {
    Hooks = {},
    Settings = {
        CaptureCallStacks = true,
        MaxClosureLogs = 2,
        MaxStackFrames = 8,
        MaxStackCapturesPerSecond = 1,
        MaxGeneratedBufferBytes = 256,
        MaxGeneratedTableEntries = 32,
        MaxGeneratedTableDepth = 8,
        MaxHexBytes = 16,
        MaxCapturedCallBytes = 4096,
        MaxCapturedArguments = 8,
        MaxRemoteHistoryBytes = 65536,
        MaxClosureHistoryBytes = 65536
    }
}
_G.isLClosure = function(value)
    return type(value) == "function"
end
_G.newCClosure = function(callback)
    return callback
end
_G.hookFunction = function(hookTarget, wrapper)
    wrappers[hookTarget] = wrapper
    return hookTarget
end
_G.restoreHook = function(record)
    record.Active = false
    return true
end
_G.getCallingScript = function()
    return nil
end
_G.getInfo = function(subject)
    if subject == externalCaller then
        return {
            func = externalCaller,
            name = "ExternalCaller",
            source = "@game/ExternalCaller.lua",
            currentline = 42
        }
    end

    return {
        func = subject,
        source = "@modules/ClosureSpy.lua"
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
            name = "ClosureSpyInternal",
            source = "@modules/ClosureSpy.lua",
            line = 100
        },
        {
            func = externalCaller,
            name = "<anonymous>",
            source = "=ReplicatedStorage.Modules.EventManagerClient",
            line = 10
        },
        {
            func = function() end,
            name = "<anonymous>",
            source = "=Players.PlayerScripts.Gameplay.C_LootDropHandler",
            line = 337
        }
    }
end

local ClosureSpy = dofile(root .. "modules/ClosureSpy.lua")
local closure = {
    Data = target,
    Name = "Target"
}
local hook = assert(ClosureSpy.Hook.new(closure))
local wrapper = assert(wrappers[target])

local first, middle, argumentCount = wrapper("first", nil, "third")
assertEqual(first, "result", "first return preserved")
assertEqual(middle, nil, "nil return preserved")
assertEqual(argumentCount, 3, "return after nil preserved")
assertEqual(hook.Calls, 1, "pre-subscriber call retained")
assertEqual(hook.Logs[1].args.n, 3, "packed argument length retained")
assertEqual(hook.Logs[1].args[3], "third", "argument after nil retained")
assertEqual(hook.Logs[1].func, externalCaller, "external caller selected")
assertEqual(hook.Logs[1].caller.name, "EventManagerClient", "anonymous caller gets a useful name")
assertEqual(
    hook.Logs[1].caller.source,
    "ReplicatedStorage.Modules.EventManagerClient",
    "caller source normalized"
)
assertEqual(hook.Logs[1].completed, true, "forwarded closure call is marked complete")
assertEqual(hook.Logs[1].forwarded, true, "forwarded closure call is marked forwarded")
assertEqual(hook.Logs[1].returns.n, 3, "closure return count retained")
assertEqual(hook.Logs[1].returns[1], "result", "closure return value retained")
assertEqual(hook.Logs[1].returns[3], 3, "closure return value after nil retained")
assertEqual(#hook.Logs[1].stack, 2, "native and internal call-stack frames filtered")
assertEqual(hook.Logs[1].stack[2].name, "C_LootDropHandler", "anonymous parent frame gets a useful name")
assertEqual(#hook.Logs[1].chain, 1, "active closure chain captured")

local emitted = 0
ClosureSpy.SetEvent(function(emittedHook, call)
    assertEqual(emittedHook, hook, "event hook")
    assertEqual(call, hook.Logs[#hook.Logs], "event uses retained call")
    emitted = emitted + 1
end)

wrapper("second")
hook:Block()
assertEqual(wrapper("blocked"), nil, "blocked call returns nil")
local blockedCall = hook.Logs[#hook.Logs]
assertEqual(originalCalls, 2, "blocked call skips original")
assertEqual(blockedCall.blocked, true, "blocked closure call is marked blocked")
assertEqual(blockedCall.forwarded, false, "blocked closure call is not forwarded")
assertEqual(emitted, 2, "subscriber receives captured calls")
assertEqual(hook.DroppedLogs, 1, "bounded history drops oldest call")
assertEqual(#hook.Logs, 2, "bounded history size")

hook:Block()
hook:IgnoreArg(2, "nil", true)
wrapper("ignored", nil)
assertEqual(originalCalls, 3, "ignored call still reaches original")
assertEqual(hook.Calls, 3, "ignored call is not captured")

hook.IgnoredArgs = {}
hook:BlockArg(2, "nil", true)
wrapper("condition-blocked", nil)
local conditionBlockedCall = hook.Logs[#hook.Logs]
assertEqual(originalCalls, 3, "nil argument block skips original")
assertEqual(hook.Calls, 4, "argument-blocked call is captured")
assertEqual(hook.DroppedLogs, 2, "retention remains bounded")

local errorRan, errorMessage = pcall(wrapper, "explode")
local errorCall = hook.Logs[#hook.Logs]
assertEqual(errorRan, false, "target error is preserved")
assertEqual(errorMessage:find("target exploded", 1, true) ~= nil, true, "target error message is preserved")
assertEqual(errorCall.completed, true, "errored closure call is marked complete")
assertEqual(errorCall.forwarded, false, "errored closure call is not marked forwarded")
assertEqual(errorCall.error:find("target exploded", 1, true) ~= nil, true, "errored closure call retains error")
assertEqual(ClosureSpy.Diagnostics.StackCapturesRateLimited > 0, true, "closure stack capture budget is enforced")

hook:DecrementCalls(errorCall)
assertEqual(#hook.Logs, 1, "closure circular history removes a logical entry")
assertEqual(hook.Logs[1], conditionBlockedCall, "closure history preserves order after removal")
assertEqual(hook.HistoryBytes, conditionBlockedCall.capturedBytes, "removal refreshes closure history bytes")

assertEqual(hook:BlockArg(0, "string", true), false, "invalid closure condition index rejected")
assertEqual(hook:BlockArg(3, 0 / 0, false), true, "closure NaN condition is accepted")
assertEqual(
    hook:AreArgsBlocked({ n = 3, [1] = true, [2] = true, [3] = 0 / 0 }),
    true,
    "closure NaN condition matches"
)
local expectedConditionBuffer = fakeBuffer.fromstring("condition")
local matchingConditionBuffer = fakeBuffer.fromstring("condition")
assertEqual(hook:BlockArg(1, expectedConditionBuffer, false), true, "closure buffer condition is accepted")
assertEqual(hook:BlockArg(1, matchingConditionBuffer, false), false, "equivalent closure buffer condition is rejected")
assertEqual(
    hook:AreArgsBlocked({ n = 1, [1] = matchingConditionBuffer }),
    true,
    "closure buffer condition matches by contents"
)

hook.BlockedArgs = {}
local identityCondition = {}
assertEqual(hook:BlockArg(2, identityCondition, false), true, "identity condition is accepted")
local callsBeforeIdentityBlock = originalCalls
wrapper("identity-conditioned", identityCondition)
local identityBlockedCall = hook.Logs[#hook.Logs]
assertEqual(originalCalls, callsBeforeIdentityBlock, "conditions run against live closure arguments")
assertEqual(identityBlockedCall.blocked, true, "live identity condition blocks the closure")
assertEqual(identityBlockedCall.args[2] == identityCondition, false, "conditioned argument is stored as a snapshot")

hook.BlockedArgs = {}
local liveTable = {
    nested = { value = "before" }
}
liveTable.self = liveTable
local returnedTable, returnedMiddle, returnedCount = wrapper("mutate-argument", liveTable)
local tableCall = hook.Logs[#hook.Logs]
assertEqual(returnedTable, liveTable, "live table return identity is preserved")
assertEqual(returnedMiddle, nil, "live nil return is preserved")
assertEqual(returnedCount, 2, "live return after nil is preserved")
assertEqual(lastSecondArgument, liveTable, "original closure receives the live table")
assertEqual(tableCall.args[2] == liveTable, false, "captured table argument is detached")
assertEqual(tableCall.args[2].self, tableCall.args[2], "captured table argument preserves cycles")
assertEqual(tableCall.args[2].changedByTarget, nil, "target mutation cannot rewrite captured arguments")
assertEqual(tableCall.returns[1] == liveTable, false, "captured table return is detached")
assertEqual(tableCall.returns[1].changedByTarget, true, "return snapshot captures the returned state")
assertEqual(tableCall.returns[1].self, tableCall.returns[1], "captured table return preserves cycles")
liveTable.nested.value = "after"
liveTable.afterReturn = true
assertEqual(tableCall.args[2].nested.value, "before", "later mutation cannot rewrite captured arguments")
assertEqual(tableCall.returns[1].nested.value, "before", "later mutation cannot rewrite captured returns")
assertEqual(tableCall.returns[1].afterReturn, nil, "later fields do not appear in captured returns")

local entryLimitedTable = {}

for index = 1, 40 do
    entryLimitedTable[index] = index
end

wrapper(entryLimitedTable)
local entryLimitCall = hook.Logs[#hook.Logs]
assertEqual(lastFirstArgument, entryLimitedTable, "table entry limiting still forwards the live table")
assertEqual(
    type(entryLimitCall.args[1].__hydroxideCaptureLimit),
    "string",
    "closure table snapshots enforce the aggregate entry limit"
)
assertEqual(entryLimitCall.replayable, false, "table entry truncation marks the snapshot incomplete")

local depthLimitedTable = {}
local depthCursor = depthLimitedTable

for _ = 1, 9 do
    depthCursor.child = {}
    depthCursor = depthCursor.child
end

wrapper(depthLimitedTable)
local depthLimitCall = hook.Logs[#hook.Logs]
local capturedDepthCursor = depthLimitCall.args[1]

for _ = 1, 8 do
    capturedDepthCursor = capturedDepthCursor.child
end

assertEqual(lastFirstArgument, depthLimitedTable, "table depth limiting still forwards the live table")
assertEqual(capturedDepthCursor.__hydroxideCaptureMarker, true, "closure table snapshots enforce the depth limit")
assertEqual(capturedDepthCursor.Kind, "table", "closure depth limit emits a table marker")
assertEqual(depthLimitCall.replayable, false, "table depth truncation marks the snapshot incomplete")

local sourceBuffer = fakeBuffer.fromstring("A\0B")
local nestedBufferArgument = { nested = sourceBuffer }
wrapper(sourceBuffer, nestedBufferArgument)
local bufferCall = hook.Logs[#hook.Logs]
assertEqual(lastFirstArgument, sourceBuffer, "original closure receives the live buffer")
sourceBuffer.bytes = "mutated"
assertEqual(fakeBuffer.tostring(bufferCall.args[1]), "A\0B", "top-level closure buffer snapshot is immutable")
assertEqual(
    fakeBuffer.tostring(bufferCall.args[2].nested),
    "A\0B",
    "nested closure buffer snapshot is immutable"
)
assertEqual(bufferCall.replayable, true, "complete closure snapshots remain replayable")

local returnedBuffer = fakeBuffer.fromstring("return-buffer")
local liveReturns = packValues(wrapper("return-many", returnedBuffer))
local returnLimitCall = hook.Logs[#hook.Logs]
assertEqual(liveReturns.n, 9, "live closure return count bypasses capture limits")
assertEqual(liveReturns[1], returnedBuffer, "live closure buffer return identity is preserved")
assertEqual(liveReturns[2], nil, "live closure nil return survives capture limits")
assertEqual(liveReturns[9], 9, "live closure tail return survives capture limits")
returnedBuffer.bytes = "mutated-return"
assertEqual(
    fakeBuffer.tostring(returnLimitCall.returns[1]),
    "return-buffer",
    "captured closure buffer return is immutable"
)
assertEqual(returnLimitCall.returns[9].__hydroxideCaptureMarker, true, "excess returns become a capture marker")
assertEqual(returnLimitCall.replayable, false, "return count truncation marks the closure snapshot incomplete")

local _, _, forwardedArgumentCount = wrapper("argument-limit", 2, 3, 4, 5, 6, 7, 8, 9)
local argumentLimitCall = hook.Logs[#hook.Logs]
assertEqual(forwardedArgumentCount, 9, "live closure argument count bypasses capture limits")
assertEqual(lastArgumentCount, 9, "original closure receives every live argument")
assertEqual(argumentLimitCall.args[8], 8, "arguments within the closure capture limit are retained")
assertEqual(argumentLimitCall.args[9].__hydroxideCaptureMarker, true, "excess closure arguments become a marker")
assertEqual(argumentLimitCall.replayable, false, "argument count truncation marks the snapshot incomplete")

local aggregateArguments = {}

for index = 1, 8 do
    aggregateArguments[index] = string.rep(string.char(64 + index), 600)
end

local _, _, aggregateForwardedCount = wrapper(unpackValues(aggregateArguments, 1, #aggregateArguments))
local aggregateCall = hook.Logs[#hook.Logs]
assertEqual(aggregateForwardedCount, 8, "aggregate byte limiting does not alter live arguments")
assertEqual(aggregateCall.args[7].__hydroxideCaptureMarker, true, "aggregate overflow becomes a marker")
assertEqual(aggregateCall.capturedBytes <= 4096, true, "aggregate closure capture bytes remain bounded")
assertEqual(aggregateCall.replayable, false, "aggregate overflow marks the closure snapshot incomplete")

local oversizedBuffer = fakeBuffer.fromstring(string.rep("x", 257))
wrapper(oversizedBuffer)
local oversizedBufferCall = hook.Logs[#hook.Logs]
assertEqual(lastFirstArgument, oversizedBuffer, "oversized buffer is still forwarded live")
assertEqual(oversizedBufferCall.args[1].__hydroxideCaptureMarker, true, "oversized closure buffer becomes a marker")
assertEqual(oversizedBufferCall.args[1].Size, 257, "oversized closure buffer marker retains its size")

local invalidBuffer = fakeBuffer.fromstring("valid")
local originalFromString = fakeBuffer.fromstring
fakeBuffer.fromstring = function()
    return nil
end
wrapper(invalidBuffer)
fakeBuffer.fromstring = originalFromString
local invalidBufferCall = hook.Logs[#hook.Logs]
assertEqual(lastFirstArgument, invalidBuffer, "buffer snapshot failure does not alter live forwarding")
assertEqual(invalidBufferCall.args[1].__hydroxideCaptureMarker, true, "buffer snapshot failure becomes a marker")
assertEqual(invalidBufferCall.replayable, false, "buffer snapshot failure marks the snapshot incomplete")
assertEqual(ClosureSpy.Diagnostics.BuffersSnapshotted >= 3, true, "closure buffer snapshots are diagnosed")
assertEqual(
    ClosureSpy.Diagnostics.BufferSnapshotsTruncated > 0,
    true,
    "truncated closure buffer snapshots are diagnosed"
)
assertEqual(ClosureSpy.Diagnostics.BufferSnapshotFailures > 0, true, "closure buffer failures are diagnosed")
assertEqual(ClosureSpy.Diagnostics.CallSnapshotsTruncated > 0, true, "truncated closure calls are diagnosed")
assertEqual(ClosureSpy.Diagnostics.LogsDropped > 0, true, "closure history eviction is diagnosed")

assertEqual(hook:Remove(), true, "hook removal succeeds")
assertEqual(closure.Data, target, "closure target restored")

hook:Clear()
assertEqual(hook.Calls, 0, "clear resets call count")
assertEqual(hook.DroppedLogs, 0, "clear resets dropped count")
assertEqual(#hook.Logs, 0, "clear removes history")
assertEqual(hook.HistoryBytes, 0, "clear resets closure history bytes")

local savedClosureHistoryBytes = oh.Settings.MaxClosureHistoryBytes
local savedRemoteHistoryBytes = oh.Settings.MaxRemoteHistoryBytes
local savedClosureLogs = oh.Settings.MaxClosureLogs
local savedCaptureCallStacks = oh.Settings.CaptureCallStacks
oh.Settings.MaxClosureHistoryBytes = nil
oh.Settings.MaxRemoteHistoryBytes = 6
oh.Settings.MaxClosureLogs = 10
oh.Settings.CaptureCallStacks = false

local FallbackClosureSpy = dofile(root .. "modules/ClosureSpy.lua")
local byteTarget = function()
    return "rr"
end
local byteClosure = {
    Data = byteTarget,
    Name = "ByteTarget"
}
local byteHook = assert(FallbackClosureSpy.Hook.new(byteClosure))
local byteWrapper = assert(wrappers[byteTarget])
byteWrapper("aa")
assertEqual(byteHook.HistoryBytes, 4, "closure history counts captured arguments and returns")
byteWrapper("bb")
assertEqual(#byteHook.Logs, 1, "return-byte refresh evicts the oldest closure call")
assertEqual(byteHook.Logs[1].args[1], "bb", "return-byte refresh retains the newest closure call")
assertEqual(byteHook.HistoryBytes, 4, "fallback closure history byte budget remains bounded")
assertEqual(byteHook.DroppedLogs, 1, "return-byte refresh records the evicted closure call")
assertEqual(byteHook.MaxHistoryBytes, 6, "closure history falls back to MaxRemoteHistoryBytes")
assertEqual(byteHook:Remove(), true, "fallback byte-budget hook removal succeeds")
byteHook:Clear()
assertEqual(byteHook.HistoryBytes, 0, "fallback byte-budget history clears")

oh.Settings.MaxClosureHistoryBytes = savedClosureHistoryBytes
oh.Settings.MaxRemoteHistoryBytes = savedRemoteHistoryBytes
oh.Settings.MaxClosureLogs = savedClosureLogs
oh.Settings.CaptureCallStacks = savedCaptureCallStacks

print("closure_spec.lua: ok")
