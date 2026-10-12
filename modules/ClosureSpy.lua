local ClosureSpy = {}
local oh = oh
local restoreHook = restoreHook

local requiredMethods = {
    ["hookFunction"] = true,
    ["newCClosure"] = true,
    ["isLClosure"] = true,
    ["withExecutorIdentity"] = true,
    ["getInfo"] = true
}

local eventCallback
local eventConnection
local callDataEvent
local Hook = {}
local hookMap = {}
local internalFunctions = setmetatable({}, { __mode = "k" })
local mainThread = {}
local activeCallChains = setmetatable({}, { __mode = "k" })
local pack = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack
local diagnostics = {
    CaptureErrors = 0,
    CallsCaptured = 0,
    CallsForwarded = 0,
    CallsBlocked = 0,
    ForwardErrors = 0,
    LogsDropped = 0,
    StackCaptures = 0,
    StackCapturesRateLimited = 0,
    BuffersSnapshotted = 0,
    BufferSnapshotsTruncated = 0,
    BufferSnapshotFailures = 0,
    CallSnapshotsTruncated = 0
}

local function safeError(value)
    local ran, message = pcall(tostring, value)
    return ran and message:sub(1, 2048) or "<unprintable error>"
end

local function recordCaptureError(stage, err)
    diagnostics.CaptureErrors = diagnostics.CaptureErrors + 1
    diagnostics.LastCaptureError = { Stage = stage, Error = safeError(err) }
end

local createLogBuffer = import("objects/LogBuffer")

if Instance and type(Instance.new) == "function" then
    local created, result = pcall(Instance.new, "BindableEvent")

    if created and result then
        callDataEvent = result

        if oh and oh.Instances then
            oh.Instances[#oh.Instances + 1] = result
        end
    end
end

local function getSetting(name, defaultValue, minimum, maximum)
    local settings = oh and oh.Settings
    local value = tonumber(settings and settings[name])

    if not value or value ~= value or value == math.huge or value == -math.huge then
        value = defaultValue
    end
    return math.max(minimum, math.min(maximum, math.floor(value)))
end

local function getMaxClosureLogs()
    return getSetting("MaxClosureLogs", 500, 1, 5000)
end

local function getMaxClosureHistoryBytes()
    local settings = oh and oh.Settings
    local function finiteNumber(value)
        value = tonumber(value)

        if not value or value ~= value or value == math.huge or value == -math.huge then
            return nil
        end

        return value
    end

    local value = finiteNumber(settings and settings.MaxClosureHistoryBytes)
        or finiteNumber(settings and settings.MaxRemoteHistoryBytes)
        or 16777216

    return math.max(1, math.min(67108864, math.floor(value)))
end

local maxClosureHistoryBytes = getMaxClosureHistoryBytes()
local maxCapturedCallBytes = math.min(
    maxClosureHistoryBytes,
    getSetting("MaxCapturedCallBytes", 262144, 4096, 8388608)
)
local maxCapturedArguments = getSetting("MaxCapturedArguments", 128, 8, 1024)
local maxCapturedBufferBytes = getSetting("MaxGeneratedBufferBytes", 65536, 256, 1048576)
local maxCapturedTableEntries = getSetting("MaxGeneratedTableEntries", 256, 8, 5000)
local maxCapturedTableDepth = getSetting("MaxGeneratedTableDepth", 16, 1, 64)
local maxCapturedBufferPreviewBytes = getSetting("MaxHexBytes", 512, 16, 65536)

local function getMaxStackFrames()
    return getSetting("MaxStackFrames", 24, 1, 256)
end

local function getMaxStackCapturesPerSecond()
    return getSetting("MaxStackCapturesPerSecond", 60, 1, 1000)
end


local function getActiveChainStorage()
    local thread = coroutine and coroutine.running and coroutine.running() or nil
    local key = thread or mainThread
    local chain = activeCallChains[key]

    if not chain then
        chain = {}
        activeCallChains[key] = chain
    end

    return chain
end

local function safeCallingScript()
    if not getCallingScript then
        return nil
    end

    local ran, result = pcall(getCallingScript)
    return ran and result or nil
end

local function safeInfo(target, options)
    if not getInfo then
        return nil
    end

    local ran, result = pcall(getInfo, target, options)
    return ran and result or nil
end

local function frameFunction(frame)
    return type(frame) == "table" and (frame.func or frame.Function) or nil
end

local function frameSource(frame)
    if type(frame) ~= "table" then
        return nil
    end

    return frame.source or frame.Source or frame.short_src or frame.shortSource
end

local function frameLine(frame)
    if type(frame) ~= "table" then
        return nil
    end

    local line = tonumber(frame.currentline or frame.currentLine or frame.line or frame.Line or frame.linedefined)

    if not line or line < 0 then
        return nil
    end

    return math.floor(line)
end

local function normalizeSource(source)
    if type(source) ~= "string" then
        return nil
    end

    source = source:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[@=]", "")
    return source ~= "" and source or nil
end

local function derivedFrameName(source)
    if type(source) ~= "string" then
        return nil
    end

    local name = source:gsub("\\", "/"):match("([^/]+)$")

    if name then
        name = name:gsub("%.lua$", ""):match("([^%.]+)$") or name
    end

    return name ~= "" and name or nil
end

local function isInternalFrame(frame)
    if type(frame) ~= "table" then
        return false
    end

    local func = frameFunction(frame)

    if func and internalFunctions[func] then
        return true
    end

    local source = normalizeSource(frameSource(frame))

    if type(source) == "string"
        and (source:find("modules/ClosureSpy.lua", 1, true) or source:find("modules\\ClosureSpy.lua", 1, true))
    then
        return true
    end

    local what = frame.what or frame.What
    return source == "[C]" or what == "C"
end

local normalizeStackFrame

local function safeExternalInfo()
    if not getInfo then
        return nil
    end

    for stackLevel = 1, getMaxStackFrames() + 16 do
        local info = safeInfo(stackLevel, "fnsl")

        if not info then
            info = safeInfo(stackLevel)
        end

        if type(info) == "table" and not isInternalFrame(info) then
            return normalizeStackFrame(info, stackLevel)
        end
    end

    return nil
end

local function safeScriptPath(script)
    if typeof(script) ~= "Instance" or not getInstancePath then
        return nil
    end

    local ran, result = pcall(getInstancePath, script)
    return ran and result or nil
end

normalizeStackFrame = function(frame, index)
    if type(frame) == "function" then
        local info = safeInfo(frame, "nslf")
        local source = info and normalizeSource(info.source or info.short_src) or nil

        return {
            index = index,
            func = frame,
            name = (info and info.name) or derivedFrameName(source) or "anonymous",
            source = source,
            shortSource = info and normalizeSource(info.short_src) or nil,
            line = info and frameLine(info) or nil,
            what = info and info.what or nil
        }
    elseif type(frame) == "table" then
        local source = normalizeSource(frameSource(frame))
        local shortSource = normalizeSource(frame.short_src or frame.shortSource)
        local name = frame.name or frame.Name

        if type(name) ~= "string" or name == "" or name == "<anonymous>" then
            name = derivedFrameName(shortSource or source) or "anonymous"
        end

        return {
            index = index,
            func = frameFunction(frame) or frame.functionValue,
            name = name,
            source = source,
            shortSource = shortSource,
            line = frameLine(frame),
            what = frame.what or frame.What,
            script = frame.script or frame.Script
        }
    elseif type(frame) == "string" then
        return {
            index = index,
            text = frame,
            name = "trace",
            source = normalizeSource(frame)
        }
    end

    return {
        index = index,
        value = frame
    }
end

local stackCaptureBudget = {
    Tokens = math.min(getMaxStackCapturesPerSecond(), 8),
    UpdatedAt = 0
}

local function reserveStackCapture()
    if not os or type(os.clock) ~= "function" then
        return true
    end

    local ran, now = pcall(os.clock)

    if not ran or type(now) ~= "number" then
        return true
    end

    local capturesPerSecond = getMaxStackCapturesPerSecond()
    local burst = math.min(capturesPerSecond, 8)
    local elapsed = math.max(0, now - stackCaptureBudget.UpdatedAt)

    stackCaptureBudget.UpdatedAt = now
    stackCaptureBudget.Tokens = math.min(
        burst,
        stackCaptureBudget.Tokens + elapsed * capturesPerSecond
    )

    if stackCaptureBudget.Tokens < 1 then
        diagnostics.StackCapturesRateLimited = diagnostics.StackCapturesRateLimited + 1
        return false
    end

    stackCaptureBudget.Tokens = stackCaptureBudget.Tokens - 1
    diagnostics.StackCaptures = diagnostics.StackCaptures + 1
    return true
end

local function captureCallStack()
    local settings = oh and oh.Settings

    if settings and settings.CaptureCallStacks == false then
        return nil, "Stack capture is disabled by configuration"
    elseif not getCallStack then
        return nil
    elseif not reserveStackCapture() then
        return nil, "Stack snapshot skipped by the performance rate limit"
    end

    local ran, stack = pcall(getCallStack, 0)

    if not ran or (type(stack) ~= "table" and type(stack) ~= "string") then
        return nil
    end

    local maxFrames = getMaxStackFrames()
    local captured = {}
    local count = 0

    if type(stack) == "string" then
        for line in stack:gmatch("[^\r\n]+") do
            count = count + 1
            captured[count] = normalizeStackFrame(line, count)

            if count >= maxFrames then
                break
            end
        end
    else
        local frames = type(stack.frames) == "table" and stack.frames or stack

        for index, frame in ipairs(frames) do
            if not isInternalFrame(frame) then
                count = count + 1
                captured[count] = normalizeStackFrame(frame, index)
            end

            if count >= maxFrames then
                break
            end
        end
    end

    return captured
end

local function captureTimestamp()
    if DateTime and type(DateTime.now) == "function" then
        local ran, now = pcall(DateTime.now)

        if ran and now and type(now.UnixTimestampMillis) == "number" then
            return now.UnixTimestampMillis / 1000
        end
    end

    return os and type(os.time) == "function" and os.time() or nil
end

local function elapsedMilliseconds(started)
    if not started or not os or type(os.clock) ~= "function" then
        return nil
    end

    local ran, finished = pcall(os.clock)
    return ran and math.max(0, (finished - started) * 1000) or nil
end

local function tailResults(results)
    local values = { n = math.max(0, results.n - 1) }

    for index = 2, results.n do
        values[index - 1] = results[index]
    end

    return values
end

local snapshotPackedValues = import("objects/ValueSnapshot").new({
    Bytes = maxCapturedCallBytes,
    Arguments = maxCapturedArguments,
    BufferBytes = maxCapturedBufferBytes,
    TableEntries = maxCapturedTableEntries,
    TableDepth = maxCapturedTableDepth,
    PreviewBytes = maxCapturedBufferPreviewBytes
}, diagnostics)

local function copyActiveCallChain(chain)
    chain = chain or getActiveChainStorage()

    local copied = {}
    local total = #chain
    local first = math.max(1, total - getMaxStackFrames() + 1)

    for index = first, total do
        local entry = chain[index]
        copied[#copied + 1] = {
            closure = entry.closure,
            closureName = entry.closureName,
            script = entry.script,
            scriptPath = entry.scriptPath,
            func = entry.func,
            source = entry.source,
            line = entry.line
        }
    end

    return copied
end

local function buildCallerInfo()
    local script = safeCallingScript()
    local stack, stackLimitation = captureCallStack()
    local info = stack and type(stack[1]) == "table" and stack[1] or nil

    if not frameFunction(info) and not stackLimitation then
        info = safeExternalInfo() or info
    end

    return {
        script = script,
        scriptPath = safeScriptPath(script),
        func = frameFunction(info),
        name = info and (info.name or info.Name) or nil,
        source = frameSource(info),
        shortSource = info and (info.shortSource or info.short_src) or nil,
        line = frameLine(info),
        stack = stack,
        limitation = stackLimitation
    }
end

local function pushActiveCall(hook, callerInfo)
    local chain = getActiveChainStorage()
    local entry = {
        chain = chain,
        hook = hook,
        closure = hook.Closure,
        closureName = hook.Closure.Name,
        script = callerInfo and callerInfo.script or nil,
        scriptPath = callerInfo and callerInfo.scriptPath or nil,
        func = callerInfo and callerInfo.func or hook.Target,
        source = callerInfo and callerInfo.source or nil,
        line = callerInfo and callerInfo.line or nil
    }

    chain[#chain + 1] = entry
    return entry
end

local function popActiveCall(entry)
    local chain = entry and entry.chain
    local index = chain and table.find(chain, entry)

    if index then
        table.remove(chain, index)
    end
end

for _, callback in ipairs({
    getActiveChainStorage,
    safeCallingScript,
    safeInfo,
    frameFunction,
    frameSource,
    frameLine,
    isInternalFrame,
    safeExternalInfo,
    safeScriptPath,
    normalizeStackFrame,
    captureCallStack,
    reserveStackCapture,
    captureTimestamp,
    snapshotPackedValues,
    copyActiveCallChain,
    buildCallerInfo,
    pushActiveCall,
    popActiveCall
}) do
    internalFunctions[callback] = true
end

local function setEvent(callback)
    if eventConnection then
        pcall(function()
            eventConnection:Disconnect()
        end)
        eventConnection = nil
    end

    eventCallback = callback

    if callDataEvent and type(callback) == "function" then
        eventConnection = callDataEvent.Event:Connect(function(...)
            pcall(callback, ...)
        end)

        if oh and oh.Events then
            oh.Events[#oh.Events + 1] = eventConnection
        end
    end
end

local function shouldCaptureCall(hook, args)
    return not hook.Ignored
        and (next(hook.IgnoredArgs) == nil or not hook:AreArgsIgnored(args))
end

local function emitCall(hook, call)
    if not eventCallback then
        return
    elseif callDataEvent then
        local fired = pcall(callDataEvent.Fire, callDataEvent, hook, call)

        if fired then
            return
        end
    end

    pcall(eventCallback, hook, call)
end

function Hook.new(closure)
    if oh and oh.Exited then
        return nil, "Hydroxide has exited"
    end
    local target = closure.Data

    if hookMap[target] then
        return false
    end

    if type(target) ~= "function" or not isLClosure(target) then
        return nil, "Only Lua closures can be spied"
    end

    local hook = {
        Closure = closure,
        Target = target,
        Calls = 0,
        DroppedLogs = 0,
        MaxHistoryBytes = maxClosureHistoryBytes,
        MaxCapturedCallBytes = maxCapturedCallBytes,
        MaxCapturedArguments = maxCapturedArguments,
        HistoryBytes = 0,
        Logs = createLogBuffer(getMaxClosureLogs(), maxClosureHistoryBytes),
        Ignored = false,
        Blocked = false,
        BlockedArgs = {},
        IgnoredArgs = {}
    }

    hook.Ignore = Hook.ignore
    hook.Block = Hook.block
    hook.IgnoreArg = Hook.ignoreArg
    hook.BlockArg = Hook.blockArg
    hook.Remove = Hook.remove
    hook.Clear = Hook.clear
    hook.AreArgsBlocked = Hook.areArgsBlocked
    hook.AreArgsIgnored = Hook.areArgsIgnored
    hook.IncrementCalls = Hook.incrementCalls
    hook.RefreshCallBytes = Hook.refreshCallBytes
    hook.DecrementCalls = Hook.decrementCalls

    local original
    local wrapper = newCClosure(function(...)
        if hook.Removed or (oh and oh.Exited) then
            return original(...)
        end
        local vargs = pack(...)
        local activeEntry
        local call
        local captured, captureError = pcall(function()
            local captureThisCall = shouldCaptureCall(hook, vargs)
            local callerInfo = captureThisCall and buildCallerInfo() or { func = target }
            activeEntry = pushActiveCall(hook, callerInfo)

            if captureThisCall then
                local args, replayable, capturedBytes = snapshotPackedValues(vargs)
                call = {
                    script = callerInfo.script,
                    func = callerInfo.func,
                    caller = callerInfo,
                    stack = callerInfo.stack,
                    chain = copyActiveCallChain(activeEntry.chain),
                    timestamp = captureTimestamp(),
                    method = "closure",
                    args = args,
                    replayable = replayable,
                    capturedBytes = capturedBytes
                }
                hook:IncrementCalls(call)
                diagnostics.CallsCaptured = diagnostics.CallsCaptured + 1
            end
        end)

        if not captured then
            recordCaptureError("arguments", captureError)
        end

        local blockChecked, blocked = pcall(function()
            return hook.Blocked
                or (next(hook.BlockedArgs) ~= nil and hook:AreArgsBlocked(vargs))
        end)

        if not blockChecked then
            diagnostics.CaptureErrors = diagnostics.CaptureErrors + 1
            blocked = false
        end

        if blocked and not (oh and oh.Exited) then
            popActiveCall(activeEntry)

            if call then
                call.blocked = true
                call.completed = true
                call.forwarded = false
                diagnostics.CallsBlocked = diagnostics.CallsBlocked + 1
                emitCall(hook, call)
            end

            return
        end

        local started = os and type(os.clock) == "function" and os.clock() or nil
        local results = pack(pcall(original, ...))
        popActiveCall(activeEntry)

        if call and not (oh and oh.Exited) then
            local finalized, finalizationError = pcall(function()
                call.blocked = false
                call.completed = true
                call.durationMs = elapsedMilliseconds(started)
                call.forwarded = results[1] == true

                if results[1] then
                    local returns, replayable, capturedBytes = snapshotPackedValues(
                        tailResults(results),
                        call.capturedBytes
                    )
                    call.returns = returns
                    call.replayable = call.replayable and replayable
                    call.capturedBytes = capturedBytes
                    hook:RefreshCallBytes(call)
                    diagnostics.CallsForwarded = diagnostics.CallsForwarded + 1
                else
                    call.error = safeError(results[2])
                    diagnostics.ForwardErrors = diagnostics.ForwardErrors + 1
                end

                emitCall(hook, call)
            end)

            if not finalized then
                recordCaptureError("returns", finalizationError)
            end
        end

        if not results[1] then
            error(results[2], 0)
        end

        return unpackValues(results, 2, results.n)
    end)
    local ran, result = pcall(hookFunction, target, wrapper)

    if not ran or type(result) ~= "function" then
        return nil, ran and "hookfunction did not return the original closure" or tostring(result)
    end

    original = result
    hook.Original = original
    hook.Record = {
        Kind = "function",
        Target = target,
        Original = original,
        Active = true
    }

    closure.Data = original
    hookMap[target] = hook
    hookMap[original] = hook
    oh.Hooks[#oh.Hooks + 1] = hook.Record

    return hook
end

function Hook.remove(hook)
    if hook.Removed then
        return true
    end
    if hook.Record and hook.Record.Active ~= false then
        local restored = restoreHook(hook.Record)

        if not restored then
            return false, "Unable to restore the original closure"
        end
    end

    hookMap[hook.Target] = nil
    hookMap[hook.Original] = nil
    hook.Closure.Data = hook.Target
    hook.Removed = true
    if oh and oh.Hooks and not oh.Exited then
        for index, record in ipairs(oh.Hooks) do
            if record == hook.Record then
                table.remove(oh.Hooks, index)
                break
            end
        end
    end
    return true
end

function Hook.clear(hook)
    hook.Calls = 0
    hook.DroppedLogs = 0
    hook.Logs:Clear()
    hook.HistoryBytes = 0
end

function Hook.block(hook)
    hook.Blocked = not hook.Blocked
end

function Hook.ignore(hook)
    hook.Ignored = not hook.Ignored
end

local ArgumentFilter = import("objects/ArgumentFilter")

function Hook.blockArg(hook, index, value, byType)
    return ArgumentFilter.Add(hook.BlockedArgs, index, value, byType)
end

function Hook.ignoreArg(hook, index, value, byType)
    return ArgumentFilter.Add(hook.IgnoredArgs, index, value, byType)
end

function Hook.areArgsBlocked(hook, args)
    return ArgumentFilter.Matches(hook.BlockedArgs, args)
end

function Hook.areArgsIgnored(hook, args)
    return ArgumentFilter.Matches(hook.IgnoredArgs, args)
end

function Hook.incrementCalls(hook, call)
    hook.Calls = hook.Calls + 1
    local dropped = hook.Logs:Push(call)

    if dropped > 0 then
        hook.DroppedLogs = hook.DroppedLogs + dropped
        diagnostics.LogsDropped = diagnostics.LogsDropped + dropped
    end

    hook.HistoryBytes = hook.Logs:Bytes()
    return dropped
end

function Hook.refreshCallBytes(hook, call)
    local dropped = hook.Logs:RefreshBytes(call)

    if dropped > 0 then
        hook.DroppedLogs = hook.DroppedLogs + dropped
        diagnostics.LogsDropped = diagnostics.LogsDropped + dropped
    end

    hook.HistoryBytes = hook.Logs:Bytes()
    return dropped
end

function Hook.decrementCalls(hook, call)
    if hook.Logs:Remove(call) then
        hook.Calls = math.max(0, hook.Calls - 1)
        hook.HistoryBytes = hook.Logs:Bytes()
    end
end

local function getActiveCallChain()
    return copyActiveCallChain()
end

ClosureSpy.Hook = Hook
ClosureSpy.CurrentClosures = hookMap
ClosureSpy.GetActiveCallChain = getActiveCallChain
ClosureSpy.SetEvent = setEvent
ClosureSpy.RequiredMethods = requiredMethods
ClosureSpy.Diagnostics = diagnostics
return ClosureSpy
