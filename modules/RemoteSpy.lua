local RemoteSpy = {}
local Remote = import("objects/Remote")

local packValues = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack

local settings = type(oh.Settings) == "table" and oh.Settings or {}
local captureExecutorCalls = settings.CaptureExecutorCalls ~= false
local captureCallStacks = settings.CaptureCallStacks ~= false
local maxStackFrames = math.max(1, math.floor(tonumber(settings.MaxStackFrames) or 24))
local maxStackCapturesPerSecond = math.max(
    1,
    math.min(1000, math.floor(tonumber(settings.MaxStackCapturesPerSecond) or 60))
)
local maxRemoteLogs = math.max(1, math.floor(tonumber(settings.MaxRemoteLogs) or 500))
local internalFunctions = setmetatable({}, { __mode = "k" })

local function registerInternal(callback)
    internalFunctions[callback] = true
    return callback
end

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
    RemoteFunction = true,
    BindableEvent = false,
    BindableFunction = false
}

local diagnostics = {
    CaptureErrors = 0,
    CallsCaptured = 0,
    CallsDeduplicated = 0,
    CallsForwarded = 0,
    CallsBlocked = 0,
    ForwardErrors = 0,
    CallsSkippedUnknownCaller = 0,
    ExecutorCallsSkipped = 0,
    LogsDropped = 0,
    RemotesDisposed = 0,
    StackCaptures = 0,
    StackCapturesRateLimited = 0,
    DirectHookAttempts = 0,
    DirectHooksInstalled = 0,
    DirectHookFailures = 0,
    OthHookAttempts = 0,
    OthHookFailures = 0,
    FunctionHookAttempts = 0,
    FunctionHookFailures = 0,
    NamecallHookInstalled = false,
    NamecallHookFailure = nil,
    LastCaptureError = nil,
    LastHookError = nil
}

local currentRemotes = setmetatable({}, { __mode = "k" })
local remoteDataEvent = Instance.new("BindableEvent")
local eventSet = false

oh.Instances[#oh.Instances + 1] = remoteDataEvent

local function recordCaptureError(stage, err)
    diagnostics.CaptureErrors = diagnostics.CaptureErrors + 1
    diagnostics.LastCaptureError = {
        Stage = stage,
        Error = tostring(err)
    }
end

local function recordHookFailure(stage, err)
    diagnostics.LastHookError = {
        Stage = stage,
        Error = tostring(err)
    }
end

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
        remote = Remote.new(instance, maxRemoteLogs)
        currentRemotes[instance] = remote

        local destroyingConnection
        local connected, connection = pcall(function()
            return instance.Destroying:Connect(function()
                if currentRemotes[instance] == remote then
                    currentRemotes[instance] = nil
                    diagnostics.RemotesDisposed = diagnostics.RemotesDisposed + 1
                end

                if destroyingConnection then
                    pcall(function()
                        destroyingConnection:Disconnect()
                    end)
                    destroyingConnection = nil
                    remote.DestroyingConnection = nil
                end
            end)
        end)

        if connected and connection then
            destroyingConnection = connection
            remote.DestroyingConnection = connection
            oh.Events[#oh.Events + 1] = connection
        end
    end

    return remote
end

local function safeCheckCaller()
    if not checkCaller then
        return nil
    end

    local ran, result = pcall(checkCaller)

    if ran then
        return result == true
    end

    return nil
end

local function safeCallingScript()
    if not getCallingScript then
        return nil
    end

    local ran, result = pcall(getCallingScript)
    return ran and result or nil
end

local function getOriginalThreadContext()
    if not othGetOriginalThread then
        return nil, nil
    end

    local threadRan, originalThread = pcall(othGetOriginalThread)

    if not threadRan or not originalThread then
        return nil, nil
    end

    if not getScriptFromThread then
        return originalThread, nil
    end

    local scriptRan, script = pcall(getScriptFromThread, originalThread)
    return originalThread, scriptRan and script or nil
end

local MAIN_THREAD = {}

local function currentThreadContext()
    local ran, thread = pcall(coroutine.running)
    return ran and thread or MAIN_THREAD
end

local function captureTimestamp()
    local ran, timestamp = pcall(function()
        return DateTime.now().UnixTimestampMillis / 1000
    end)

    if ran and type(timestamp) == "number" then
        return timestamp
    end

    return os.time()
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
        and (source:find("modules/RemoteSpy.lua", 1, true) or source:find("modules\\RemoteSpy.lua", 1, true))
    then
        return true
    end

    local what = frame.what or frame.What
    return source == "[C]" or what == "C"
end

local function normalizeStackFrame(frame, index)
    if type(frame) == "string" then
        return {
            index = index,
            text = frame,
            name = "trace",
            source = frame
        }
    elseif type(frame) ~= "table" then
        return {
            index = index,
            value = frame,
            name = "unknown"
        }
    end

    local source = normalizeSource(frameSource(frame))
    local shortSource = normalizeSource(frame.short_src or frame.shortSource)
    local name = frame.name or frame.Name

    if type(name) ~= "string" or name == "" or name == "<anonymous>" then
        name = derivedFrameName(shortSource or source) or "anonymous"
    end

    return {
        index = index,
        func = frameFunction(frame),
        name = name,
        source = source,
        shortSource = shortSource,
        line = frameLine(frame),
        what = frame.what or frame.What,
        script = frame.script or frame.Script
    }
end

local function safeGetInfo()
    if not getInfo then
        return nil
    end

    for stackLevel = 1, maxStackFrames + 16 do
        local ran, info = pcall(getInfo, stackLevel, "fnsl")

        if not ran then
            ran, info = pcall(getInfo, stackLevel)
        end

        if ran and type(info) == "table" and not isInternalFrame(info) then
            return normalizeStackFrame(info, stackLevel)
        end
    end

    return nil
end

local function filterCallStack(stack)
    local frames = {}

    if type(stack) == "string" then
        for line in stack:gmatch("[^\r\n]+") do
            frames[#frames + 1] = normalizeStackFrame(line, #frames + 1)

            if #frames >= maxStackFrames then
                break
            end
        end
    elseif type(stack) == "table" then
        local source = type(stack.frames) == "table" and stack.frames or stack

        for index = 1, #source do
            local frame = source[index]

            if not isInternalFrame(frame) then
                frames[#frames + 1] = normalizeStackFrame(frame, index)
            end

            if #frames >= maxStackFrames then
                break
            end
        end
    end

    return frames
end

local stackCaptureBudget = {
    Tokens = math.min(maxStackCapturesPerSecond, 8),
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

    local elapsed = math.max(0, now - stackCaptureBudget.UpdatedAt)
    local burst = math.min(maxStackCapturesPerSecond, 8)

    stackCaptureBudget.UpdatedAt = now
    stackCaptureBudget.Tokens = math.min(
        burst,
        stackCaptureBudget.Tokens + elapsed * maxStackCapturesPerSecond
    )

    if stackCaptureBudget.Tokens < 1 then
        diagnostics.StackCapturesRateLimited = diagnostics.StackCapturesRateLimited + 1
        return false
    end

    stackCaptureBudget.Tokens = stackCaptureBudget.Tokens - 1
    diagnostics.StackCaptures = diagnostics.StackCaptures + 1
    return true
end

local function safeGetCallStack(offThread)
    if offThread then
        return nil, "OTH callbacks run off-thread; a structured stack is unavailable"
    elseif not captureCallStacks then
        return nil, "Stack capture is disabled by configuration"
    elseif not getCallStack then
        return nil
    elseif not reserveStackCapture() then
        return nil, "Stack snapshot skipped by the performance rate limit"
    end

    local ran, stack = pcall(getCallStack, 0)

    if not ran then
        recordCaptureError("call-stack", stack)
        return nil
    end

    return filterCallStack(stack)
end

local function buildCall(vargs, capture)
    local stack, stackLimitation = safeGetCallStack(capture.OffThread)
    local info = stack and type(stack[1]) == "table" and stack[1] or nil

    if not info and not capture.OffThread and not stackLimitation then
        info = safeGetInfo()
    end

    local script = capture.CallingScript

    if not capture.CallingScriptResolved then
        script = safeCallingScript()
    end

    local limitation

    limitation = stackLimitation

    return {
        script = script,
        args = vargs,
        func = frameFunction(info),
        method = capture.Method,
        timestamp = captureTimestamp(),
        offThread = capture.OffThread,
        stack = stack,
        caller = {
            script = script,
            func = frameFunction(info),
            name = info and info.name,
            source = info and info.source,
            shortSource = info and info.shortSource,
            line = info and info.line,
            isExecutor = capture.IsExecutor,
            captureSource = capture.Source,
            offThread = capture.OffThread,
            limitation = limitation
        }
    }
end

local function processRemoteCall(instance, method, vargs, capture)
    if typeof(instance) ~= "Instance" then
        return false, nil
    end

    method = normalizeMethod(method)
    capture.Method = method

    if not remotesViewing[instance.ClassName] or instance == remoteDataEvent or not remoteMethods[method] then
        return false, nil
    end

    if not captureExecutorCalls and capture.IsExecutor ~= false then
        if capture.IsExecutor == true then
            diagnostics.ExecutorCallsSkipped = diagnostics.ExecutorCallsSkipped + 1
        else
            diagnostics.CallsSkippedUnknownCaller = diagnostics.CallsSkippedUnknownCaller + 1
        end

        return false, nil
    end

    local remote = ensureRemote(instance)
    local argsIgnored = next(remote.IgnoredArgs) ~= nil and remote:AreArgsIgnored(vargs)
    local argsBlocked = next(remote.BlockedArgs) ~= nil and remote:AreArgsBlocked(vargs)

    local call

    if not remote.Ignored and not argsIgnored then
        call = buildCall(vargs, capture)

        local dropped = remote:IncrementCalls(call)

        diagnostics.CallsCaptured = diagnostics.CallsCaptured + 1

        if dropped then
            diagnostics.LogsDropped = diagnostics.LogsDropped + 1
        end

    end

    return remote.Blocked or argsBlocked, call
end

local function safeProcessRemoteCall(instance, method, vargs, capture)
    local ran, blocked, call = pcall(processRemoteCall, instance, method, vargs, capture)

    if not ran then
        recordCaptureError(capture.Source, blocked)
        return false, nil
    end

    return blocked == true, call
end

local function emitCall(instance, call)
    if call and eventSet then
        local ran, err = pcall(remoteDataEvent.Fire, remoteDataEvent, instance, call)

        if not ran then
            recordCaptureError("call-event", err)
        end
    end
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

local activeCalls = setmetatable({}, { __mode = "k" })

local function getActiveMethods(context, instance, create)
    local byInstance = activeCalls[context]

    if not byInstance and create then
        byInstance = setmetatable({}, { __mode = "k" })
        activeCalls[context] = byInstance
    end

    local methods = byInstance and byInstance[instance]

    if not methods and create then
        methods = {}
        byInstance[instance] = methods
    end

    return methods
end

local function beginCapture(context, instance, method, source)
    local methods = getActiveMethods(context, instance, true)
    local previous = methods[method]

    methods[method] = source
    return previous, previous ~= nil and previous ~= source
end

local function endCapture(context, instance, method, previous)
    local methods = getActiveMethods(context, instance, false)

    if methods then
        methods[method] = previous
    end
end

local function tailArguments(arguments)
    local result = { n = math.max(0, arguments.n - 1) }

    for index = 2, arguments.n do
        result[index - 1] = arguments[index]
    end

    return result
end

local function invokeOriginal(original, arguments)
    if type(original) ~= "function" then
        error("RemoteSpy hook could not resolve the original callback", 0)
    end

    return original(unpackValues(arguments, 1, arguments.n))
end

local function runHook(original, method, capture, arguments)
    local instance = arguments[1]

    if typeof(instance) ~= "Instance" then
        return invokeOriginal(original, arguments)
    end

    method = normalizeMethod(method)

    if not remoteMethods[method] then
        return invokeOriginal(original, arguments)
    end

    local previous, duplicate = beginCapture(capture.Context, instance, method, capture.Source)
    local blocked = false
    local call

    if duplicate then
        diagnostics.CallsDeduplicated = diagnostics.CallsDeduplicated + 1
    else
        blocked, call = safeProcessRemoteCall(instance, method, tailArguments(arguments), capture)
    end

    if blocked then
        endCapture(capture.Context, instance, method, previous)

        if call then
            call.blocked = true
            call.completed = true
            call.forwarded = false
            diagnostics.CallsBlocked = diagnostics.CallsBlocked + 1
            emitCall(instance, call)
        end

        return
    end

    local started = os and type(os.clock) == "function" and os.clock() or nil
    local results = packValues(pcall(invokeOriginal, original, arguments))

    endCapture(capture.Context, instance, method, previous)

    if call then
        call.blocked = false
        call.completed = true
        call.durationMs = elapsedMilliseconds(started)
        call.forwarded = results[1] == true

        if results[1] then
            call.returns = tailResults(results)
            diagnostics.CallsForwarded = diagnostics.CallsForwarded + 1
        else
            call.error = tostring(results[2])
            diagnostics.ForwardErrors = diagnostics.ForwardErrors + 1
        end

        emitCall(instance, call)
    end

    if not results[1] then
        error(results[2], 0)
    end

    return unpackValues(results, 2, results.n)
end

local function createDirectHookCallback(targetMethod, offThread)
    local callback = function(original, ...)
        local originalThread, callingScript

        if offThread then
            originalThread, callingScript = getOriginalThreadContext()
        end

        local capture = {
            Source = offThread and "direct-oth" or "direct-function",
            Context = originalThread or currentThreadContext(),
            CallingScript = callingScript,
            CallingScriptResolved = offThread,
            IsExecutor = offThread and nil or safeCheckCaller(),
            OffThread = offThread
        }

        return runHook(original, targetMethod, capture, packValues(...))
    end

    return registerInternal(callback)
end

local function installDirectHook(target, targetMethod)
    diagnostics.DirectHookAttempts = diagnostics.DirectHookAttempts + 1
    local lastFailure

	-- Potassium documents oth.get_root_callback() as the authoritative
	-- pass-through inside hook threads. Some builds also return the original
	-- callback from oth.hook, which is retained strictly as a compatibility
	-- fallback so a root-callback lookup failure does not swallow the call.
    if othHook and othGetRootCallback and othUnhook then
        diagnostics.OthHookAttempts = diagnostics.OthHookAttempts + 1
		local callback = createDirectHookCallback(targetMethod, true)
		local installedOriginal
		local othCallback = registerInternal(function(...)
			local rootRan, rootCallback = pcall(othGetRootCallback)
			local original = rootRan and type(rootCallback) == "function" and rootCallback or installedOriginal

			if type(original) ~= "function" then
				recordCaptureError("oth-root-callback", rootCallback)
				error("RemoteSpy could not resolve the OTH root callback", 0)
			end

            return callback(original, ...)
        end)
        local ran, result = pcall(othHook, target, othCallback)

        if ran and result ~= false then
            installedOriginal = type(result) == "function" and result or nil
            oh.Hooks[#oh.Hooks + 1] = {
                Kind = "oth",
                Target = target,
                Original = installedOriginal,
                Active = true
            }
            diagnostics.DirectHooksInstalled = diagnostics.DirectHooksInstalled + 1
            return true
        end

        diagnostics.OthHookFailures = diagnostics.OthHookFailures + 1
        lastFailure = ran and "othHook returned false" or result
    end

    if hookFunction then
        diagnostics.FunctionHookAttempts = diagnostics.FunctionHookAttempts + 1
        local original
        local callback = createDirectHookCallback(targetMethod, false)
        local callbackWrapper = function(...)
            return callback(original, ...)
        end
        registerInternal(callbackWrapper)

        local wrapper = registerInternal(newCClosure and newCClosure(callbackWrapper) or callbackWrapper)
        local ran, result = pcall(hookFunction, target, wrapper)

        if ran and type(result) == "function" then
            original = result
            oh.Hooks[#oh.Hooks + 1] = {
                Kind = "function",
                Target = target,
                Original = original,
                Active = true
            }
            diagnostics.DirectHooksInstalled = diagnostics.DirectHooksInstalled + 1
            return true
        end

        diagnostics.FunctionHookFailures = diagnostics.FunctionHookFailures + 1
        lastFailure = ran and "hookFunction did not return the original closure" or result
    end

    diagnostics.DirectHookFailures = diagnostics.DirectHookFailures + 1
    recordHookFailure("direct-hook", lastFailure or "No supported direct-hook API was available")
    return false
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

    return targetRan and type(target) == "function" and target or nil
end

registerInternal(safeGetInfo)
registerInternal(safeGetCallStack)
registerInternal(normalizeStackFrame)
registerInternal(buildCall)
registerInternal(processRemoteCall)
registerInternal(safeProcessRemoteCall)
registerInternal(emitCall)
registerInternal(runHook)

local directTargets = {
    { "RemoteEvent", "FireServer" },
    { "UnreliableRemoteEvent", "FireServer" },
    { "RemoteFunction", "InvokeServer" },
    { "BindableEvent", "Fire" },
    { "BindableFunction", "Invoke" }
}
local targetGroups = {}
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
    if installDirectHook(target, group.Method) then
        installedDirectHook = true
    end
end

local installedNamecallHook = false

if hookMetaMethod and getNamecallMethod then
    local metatable = getMetatable and getMetatable(game)
    local target = metatable and metatable.__namecall
    local originalNamecall
    local callback = function(...)
        local arguments = packValues(...)
        local methodRan, method = pcall(getNamecallMethod)

        if not methodRan then
            recordCaptureError("namecall-method", method)
            return invokeOriginal(originalNamecall, arguments)
        end

        local capture = {
            Source = "namecall",
            Context = currentThreadContext(),
            CallingScript = nil,
            CallingScriptResolved = false,
            IsExecutor = safeCheckCaller(),
            OffThread = false
        }

        return runHook(originalNamecall, method, capture, arguments)
    end
    registerInternal(callback)

    local wrapper = registerInternal(newCClosure and newCClosure(callback) or callback)
    local ran, original = pcall(hookMetaMethod, game, "__namecall", wrapper)

    if ran and type(original) == "function" then
        originalNamecall = original
        installedNamecallHook = true
        diagnostics.NamecallHookInstalled = true
        oh.Hooks[#oh.Hooks + 1] = {
            Kind = "metamethod",
            Target = target,
            Object = game,
            Method = "__namecall",
            Original = original,
            Active = true
        }
    else
        diagnostics.NamecallHookFailure = tostring(ran and "hookMetaMethod did not return the original closure" or original)
        recordHookFailure("namecall", diagnostics.NamecallHookFailure)
    end
else
    diagnostics.NamecallHookFailure = "hookMetaMethod or getNamecallMethod is unavailable"
end

RemoteSpy.RemotesViewing = remotesViewing
RemoteSpy.CurrentRemotes = currentRemotes
RemoteSpy.ConnectEvent = connectEvent
RemoteSpy.RequiredMethods = requiredMethods
RemoteSpy.Diagnostics = diagnostics
RemoteSpy.IsSupported = installedDirectHook or installedNamecallHook
return RemoteSpy
