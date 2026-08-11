local ClosureSpy = {}

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

local function createLogBuffer(capacity, byteCapacity)
    local storage = {}
    local sizes = {}
    local head = 1
    local count = 0
    local storedBytes = 0
    local methods = {}
    local proxy = {}

    local function physicalIndex(logicalIndex)
        return ((head + logicalIndex - 2) % capacity) + 1
    end

    local function valueBytes(value)
        return math.max(0, math.floor(tonumber(type(value) == "table" and value.capturedBytes) or 0))
    end

    local function popOldest()
        if count == 0 then
            return nil
        end

        local dropped = storage[head]
        storedBytes = math.max(0, storedBytes - (sizes[head] or 0))
        storage[head] = nil
        sizes[head] = nil
        head = (head % capacity) + 1
        count = count - 1

        if count == 0 then
            head = 1
        end

        return dropped
    end

    function methods.Push(_, value)
        local bytes = valueBytes(value)
        local dropped = 0

        while count > 0 and (count >= capacity or storedBytes + bytes > byteCapacity) do
            popOldest()
            dropped = dropped + 1
        end

        count = count + 1
        local index = physicalIndex(count)
        storage[index] = value
        sizes[index] = bytes
        storedBytes = storedBytes + bytes
        return dropped
    end

    function methods.RefreshBytes(_, target)
        local found

        for logicalIndex = 1, count do
            if storage[physicalIndex(logicalIndex)] == target then
                found = physicalIndex(logicalIndex)
                break
            end
        end

        if not found then
            return 0
        end

        local nextBytes = valueBytes(target)
        storedBytes = math.max(0, storedBytes - (sizes[found] or 0)) + nextBytes
        sizes[found] = nextBytes

        local dropped = 0

        while count > 1 and storedBytes > byteCapacity do
            popOldest()
            dropped = dropped + 1
        end

        return dropped
    end

    function methods.Remove(_, target)
        local found

        for logicalIndex = 1, count do
            if storage[physicalIndex(logicalIndex)] == target then
                found = logicalIndex
                break
            end
        end

        if not found then
            return false
        end

        storedBytes = math.max(0, storedBytes - (sizes[physicalIndex(found)] or 0))

        for logicalIndex = found, count - 1 do
            local index = physicalIndex(logicalIndex)
            local nextIndex = physicalIndex(logicalIndex + 1)
            storage[index] = storage[nextIndex]
            sizes[index] = sizes[nextIndex]
        end

        local lastIndex = physicalIndex(count)
        storage[lastIndex] = nil
        sizes[lastIndex] = nil
        count = count - 1

        if count == 0 then
            head = 1
        end

        return true
    end

    function methods.Clear()
        storage = {}
        sizes = {}
        head = 1
        count = 0
        storedBytes = 0
    end

    function methods.Bytes()
        return storedBytes
    end

    local function iterate()
        local logicalIndex = 0

        return function()
            logicalIndex = logicalIndex + 1

            if logicalIndex <= count then
                return logicalIndex, storage[physicalIndex(logicalIndex)]
            end
        end
    end

    return setmetatable(proxy, {
        __len = function()
            return count
        end,
        __index = function(_, key)
            if type(key) == "number" and key >= 1 and key <= count and key % 1 == 0 then
                return storage[physicalIndex(key)]
            end

            return methods[key]
        end,
        __iter = iterate,
        __pairs = iterate
    })
end

if Instance and type(Instance.new) == "function" then
    local created, result = pcall(Instance.new, "BindableEvent")

    if created and result then
        callDataEvent = result

        if oh and oh.Instances then
            oh.Instances[#oh.Instances + 1] = result
        end
    end
end

local function getSetting(name, defaultValue)
    local settings = oh and oh.Settings
    local value = settings and settings[name]

    if type(value) == "number" then
        return value
    end

    return defaultValue
end

local function getMaxClosureLogs()
    return math.max(1, math.floor(getSetting("MaxClosureLogs", 500)))
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

    return math.max(1, math.floor(value))
end

local maxClosureHistoryBytes = getMaxClosureHistoryBytes()
local maxCapturedCallBytes = math.min(
    maxClosureHistoryBytes,
    math.max(4096, math.floor(getSetting("MaxCapturedCallBytes", 262144)))
)
local maxCapturedArguments = math.max(
    8,
    math.min(1024, math.floor(getSetting("MaxCapturedArguments", 128)))
)
local maxCapturedBufferBytes = math.max(256, math.floor(getSetting("MaxGeneratedBufferBytes", 65536)))
local maxCapturedTableEntries = math.max(8, math.floor(getSetting("MaxGeneratedTableEntries", 256)))
local maxCapturedTableDepth = math.max(1, math.floor(getSetting("MaxGeneratedTableDepth", 16)))
local maxCapturedBufferPreviewBytes = math.max(16, math.floor(getSetting("MaxHexBytes", 512)))

local function getMaxStackFrames()
    return math.max(1, math.floor(getSetting("MaxStackFrames", 24)))
end

local function getMaxStackCapturesPerSecond()
    return math.max(1, math.min(1000, math.floor(getSetting("MaxStackCapturesPerSecond", 60))))
end

local function argumentCount(args)
    if type(args) ~= "table" then
        return 0
    elseif type(args.n) == "number" then
        return math.max(0, math.floor(args.n))
    end

    return #args
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

local function makeCaptureMarker(kind, detail)
    return {
        __hydroxideCaptureMarker = true,
        Kind = kind,
        Detail = detail
    }
end

local function readBufferPreview(value, length, maximum)
    if not buffer or type(buffer.readu8) ~= "function" then
        return nil
    end

    local shown = math.min(length, maximum or maxCapturedBufferPreviewBytes)
    local parts = {}
    local ran = pcall(function()
        for offset = 0, shown - 1 do
            parts[offset + 1] = string.char(buffer.readu8(value, offset))
        end
    end)

    return ran and table.concat(parts) or nil
end

local function reserveCaptureBytes(state, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))

    if state.Bytes + amount > maxCapturedCallBytes then
        state.Replayable = false
        state.Truncated = true
        return false
    end

    state.Bytes = state.Bytes + amount
    return true
end

local function addBoundedBufferPreview(marker, value, length, state)
    local remaining = math.max(0, maxCapturedCallBytes - state.Bytes)
    local shown = math.min(length, maxCapturedBufferPreviewBytes, remaining)

    if shown > 0 then
        marker.Preview = readBufferPreview(value, length, shown)

        if marker.Preview then
            reserveCaptureBytes(state, #marker.Preview)
        end
    end
end

local function snapshotBuffer(value, state)
    if not buffer
        or type(buffer.len) ~= "function"
        or type(buffer.tostring) ~= "function"
        or type(buffer.fromstring) ~= "function"
    then
        diagnostics.BufferSnapshotFailures = diagnostics.BufferSnapshotFailures + 1
        state.Replayable = false
        return makeCaptureMarker("buffer", "Buffer copy APIs are unavailable")
    end

    local measured, length = pcall(buffer.len, value)

    if not measured
        or type(length) ~= "number"
        or length ~= length
        or length < 0
        or length == math.huge
        or length % 1 ~= 0
    then
        diagnostics.BufferSnapshotFailures = diagnostics.BufferSnapshotFailures + 1
        state.Replayable = false
        return makeCaptureMarker("buffer", "Buffer length could not be read")
    elseif length > maxCapturedBufferBytes then
        diagnostics.BufferSnapshotsTruncated = diagnostics.BufferSnapshotsTruncated + 1
        state.Replayable = false
        state.Truncated = true
        local marker = makeCaptureMarker(
            "buffer",
            ("%d-byte buffer exceeds the %d-byte capture limit"):format(length, maxCapturedBufferBytes)
        )
        marker.Size = length
        addBoundedBufferPreview(marker, value, length, state)
        return marker
    elseif not reserveCaptureBytes(state, length) then
        diagnostics.BufferSnapshotsTruncated = diagnostics.BufferSnapshotsTruncated + 1
        local marker = makeCaptureMarker(
            "buffer",
            ("Aggregate call capture exceeds the %d-byte limit"):format(maxCapturedCallBytes)
        )
        marker.Size = length
        addBoundedBufferPreview(marker, value, length, state)
        return marker
    end

    local copied, bytes = pcall(buffer.tostring, value)

    if not copied or type(bytes) ~= "string" or #bytes ~= length then
        diagnostics.BufferSnapshotFailures = diagnostics.BufferSnapshotFailures + 1
        state.Replayable = false
        return makeCaptureMarker("buffer", "Buffer contents could not be copied")
    end

    local rebuilt, snapshot = pcall(buffer.fromstring, bytes)

    if not rebuilt or typeof(snapshot) ~= "buffer" then
        diagnostics.BufferSnapshotFailures = diagnostics.BufferSnapshotFailures + 1
        state.Replayable = false
        return makeCaptureMarker("buffer", "Buffer snapshot could not be created")
    end

    local measuredSnapshot, snapshotLength = pcall(buffer.len, snapshot)

    if not measuredSnapshot or snapshotLength ~= length then
        diagnostics.BufferSnapshotFailures = diagnostics.BufferSnapshotFailures + 1
        state.Replayable = false
        return makeCaptureMarker("buffer", "Buffer snapshot length did not match the source")
    end

    diagnostics.BuffersSnapshotted = diagnostics.BuffersSnapshotted + 1
    return snapshot
end

local function snapshotPackedValues(values, initialBytes)
    local state = {
        Replayable = true,
        Entries = 0,
        Bytes = math.min(
            maxCapturedCallBytes,
            math.max(0, math.floor(tonumber(initialBytes) or 0))
        ),
        Truncated = false
    }
    local seen = setmetatable({}, { __mode = "k" })

    local clone
    clone = function(value, depth)
        local valueType = typeof(value)

        if valueType == "buffer" then
            return snapshotBuffer(value, state)
        elseif type(value) == "string" then
            if reserveCaptureBytes(state, #value) then
                return value
            end

            local marker = makeCaptureMarker(
                "string",
                ("Aggregate call capture exceeds the %d-byte limit"):format(maxCapturedCallBytes)
            )
            marker.Size = #value
            local remaining = math.max(0, maxCapturedCallBytes - state.Bytes)
            local shown = math.min(#value, maxCapturedBufferPreviewBytes, remaining)

            if shown > 0 then
                marker.Preview = value:sub(1, shown)
                reserveCaptureBytes(state, #marker.Preview)
            end

            return marker
        elseif type(value) ~= "table" then
            return value
        elseif seen[value] then
            return seen[value]
        elseif depth >= maxCapturedTableDepth then
            state.Replayable = false
            state.Truncated = true
            return makeCaptureMarker("table", "Nested table exceeds the capture depth limit")
        end

        local copy = {}
        seen[value] = copy

        for key, nestedValue in next, value do
            state.Entries = state.Entries + 1

            if state.Entries > maxCapturedTableEntries then
                state.Replayable = false
                state.Truncated = true
                copy.__hydroxideCaptureLimit = "Additional entries were omitted by the capture limit"
                break
            end

            copy[clone(key, depth + 1)] = clone(nestedValue, depth + 1)
        end

        return copy
    end

    local originalCount = type(values) == "table" and tonumber(values.n) or nil

    if not originalCount
        or originalCount ~= originalCount
        or originalCount == math.huge
        or originalCount == -math.huge
    then
        originalCount = type(values) == "table" and #values or 0
    end

    originalCount = math.max(0, math.floor(originalCount))
    local count = math.min(originalCount, maxCapturedArguments)
    local snapshot = { n = count }

    for index = 1, count do
        snapshot[index] = clone(values[index], 0)
    end

    if originalCount > count then
        state.Replayable = false
        state.Truncated = true
        snapshot.n = count + 1
        snapshot[count + 1] = makeCaptureMarker(
            "arguments",
            ("%d additional arguments were omitted by the capture limit"):format(originalCount - count)
        )
    end

    if state.Truncated then
        diagnostics.CallSnapshotsTruncated = diagnostics.CallSnapshotsTruncated + 1
    end

    return snapshot, state.Replayable, state.Bytes
end

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
    makeCaptureMarker,
    readBufferPreview,
    reserveCaptureBytes,
    addBoundedBufferPreview,
    snapshotBuffer,
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
            diagnostics.CaptureErrors = diagnostics.CaptureErrors + 1

            if type(warn) == "function" then
                warn("[Hydroxide] ClosureSpy capture failed: " .. tostring(captureError))
            end
        end

        local blockChecked, blocked = pcall(function()
            return hook.Blocked
                or (next(hook.BlockedArgs) ~= nil and hook:AreArgsBlocked(vargs))
        end)

        if not blockChecked then
            diagnostics.CaptureErrors = diagnostics.CaptureErrors + 1
            blocked = false
        end

        if blocked then
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

        if call then
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
                    call.error = tostring(results[2])
                    diagnostics.ForwardErrors = diagnostics.ForwardErrors + 1
                end

                emitCall(hook, call)
            end)

            if not finalized then
                diagnostics.CaptureErrors = diagnostics.CaptureErrors + 1

                if type(warn) == "function" then
                    warn("[Hydroxide] ClosureSpy return capture failed: " .. tostring(finalizationError))
                end
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
    if hook.Record and hook.Record.Active ~= false then
        local restored = restoreHook(hook.Record)

        if not restored then
            return false, "Unable to restore the original closure"
        end
    end

    hookMap[hook.Target] = nil
    hookMap[hook.Original] = nil
    hook.Closure.Data = hook.Target
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

local buffersEqual

local function addArgCondition(storage, index, value, byType)
    index = tonumber(index)

    if not index or index ~= index or index == math.huge or index == -math.huge or index < 1 or index % 1 ~= 0 then
        return false, "Argument index must be a positive integer"
    end

    local condition = storage[index]

    if not condition then
        condition = {
            types = {},
            values = {},
            nan = false
        }
        storage[index] = condition
    end

    if byType or value == nil then
        local valueType = byType and value or "nil"

        if type(valueType) ~= "string" or valueType == "" then
            return false, "Condition type must be a non-empty string"
        elseif condition.types[valueType] then
            return false, "Condition already exists"
        end

        condition.types[valueType] = true
    elseif type(value) == "number" and value ~= value then
        if condition.nan then
            return false, "Condition already exists"
        end

        condition.nan = true
    else
        if typeof(value) == "buffer" then
            for expected in pairs(condition.values) do
                if typeof(expected) == "buffer" and buffersEqual(expected, value) then
                    return false, "Condition already exists"
                end
            end
        end

        if condition.values[value] ~= nil then
            return false, "Condition already exists"
        end

        condition.values[value] = true
    end

    return true
end

function Hook.blockArg(hook, index, value, byType)
    return addArgCondition(hook.BlockedArgs, index, value, byType)
end

function Hook.ignoreArg(hook, index, value, byType)
    return addArgCondition(hook.IgnoredArgs, index, value, byType)
end

buffersEqual = function(left, right)
    if left == right then
        return true
    elseif typeof(left) ~= "buffer" or typeof(right) ~= "buffer" or not buffer then
        return false
    elseif type(buffer.len) ~= "function" or type(buffer.readu8) ~= "function" then
        return false
    end

    local maximum = 4096

    if oh and oh.Settings then
        maximum = tonumber(oh.Settings.MaxConditionBufferBytes or oh.Settings.maxConditionBufferBytes) or maximum
    end

    local ran, matches = pcall(function()
        local leftLength = buffer.len(left)
        local rightLength = buffer.len(right)

        if leftLength ~= rightLength or leftLength > maximum then
            return false
        end

        for offset = 0, leftLength - 1 do
            if buffer.readu8(left, offset) ~= buffer.readu8(right, offset) then
                return false
            end
        end

        return true
    end)

    return ran and matches == true
end


local function matchesConditionValues(condition, value)
    if value == nil then
        return false
    elseif type(value) == "number" and value ~= value then
        return condition.nan == true
    elseif condition.values[value] ~= nil then
        return true
    elseif typeof(value) == "buffer" then
        for expected in pairs(condition.values) do
            if typeof(expected) == "buffer" and buffersEqual(expected, value) then
                return true
            end
        end
    end

    return false
end

local function matchesArgCondition(storage, args)
    for index = 1, argumentCount(args) do
        local value = args[index]
        local condition = storage[index]

        if condition
            and (condition.types[typeof(value)] or matchesConditionValues(condition, value))
        then
            return true
        end
    end

    return false
end

function Hook.areArgsBlocked(hook, args)
    return matchesArgCondition(hook.BlockedArgs, args)
end

function Hook.areArgsIgnored(hook, args)
    return matchesArgCondition(hook.IgnoredArgs, args)
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
