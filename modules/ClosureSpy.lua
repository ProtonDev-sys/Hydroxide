local ClosureSpy = {}

local requiredMethods = {
    ["hookFunction"] = true,
    ["newCClosure"] = true,
    ["isLClosure"] = true,
    ["getProtos"] = true,
    ["getUpvalues"] = true,
    ["getUpvalue"] = true,
    ["withThreadIdentity"] = true,
    ["setUpvalue"] = true,
    ["getConstants"] = true,
    ["getConstant"] = true,
    ["setConstant"] = true,
    ["getInfo"] = true
}

local eventCallback
local Hook = {}
local hookMap = {}

local function safeCallingScript()
    if not getCallingScript then
        return nil
    end

    local ran, result = pcall(getCallingScript)
    return ran and result or nil
end

local function setEvent(callback)
    eventCallback = callback
end

local function emitCall(hook, vargs)
    if not eventCallback
        or hook.Ignored
        or (next(hook.IgnoredArgs) ~= nil and hook:AreArgsIgnored(vargs))
    then
        return
    end

    pcall(eventCallback, hook, {
        script = safeCallingScript(),
        args = vargs
    })
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
        Logs = {},
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
    hook.DecrementCalls = Hook.decrementCalls

    local original
    local wrapper = newCClosure(function(...)
        local vargs = { ... }

        emitCall(hook, vargs)

        if not hook.Blocked
            and (next(hook.BlockedArgs) == nil or not hook:AreArgsBlocked(vargs))
        then
            return original(...)
        end
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
    hook.Logs = {}
end

function Hook.block(hook)
    hook.Blocked = not hook.Blocked
end

function Hook.ignore(hook)
    hook.Ignored = not hook.Ignored
end

local function addArgCondition(storage, index, value, byType)
    local condition = storage[index]

    if not condition then
        condition = {
            types = {},
            values = {}
        }
        storage[index] = condition
    end

    if byType then
        condition.types[value] = true
    else
        condition.values[value] = true
    end
end

function Hook.blockArg(hook, index, value, byType)
    addArgCondition(hook.BlockedArgs, index, value, byType)
end

function Hook.ignoreArg(hook, index, value, byType)
    addArgCondition(hook.IgnoredArgs, index, value, byType)
end

local function matchesArgCondition(storage, args)
    for index, value in pairs(args) do
        local condition = storage[index]

        if condition and (condition.types[typeof(value)] or condition.values[value] ~= nil) then
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
    hook.Logs[#hook.Logs + 1] = call
end

function Hook.decrementCalls(hook, call)
    local index = table.find(hook.Logs, call)

    if index then
        table.remove(hook.Logs, index)
        hook.Calls = math.max(0, hook.Calls - 1)
    end
end

ClosureSpy.Hook = Hook
ClosureSpy.CurrentClosures = hookMap
ClosureSpy.SetEvent = setEvent
ClosureSpy.RequiredMethods = requiredMethods
return ClosureSpy
