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

_G.typeof = _G.typeof or type

local wrappers = {}
local originalCalls = 0
local externalCaller = function() end
local target = function(...)
    originalCalls = originalCalls + 1
    return "result", nil, select("#", ...)
end

_G.oh = {
    Hooks = {},
    Settings = {
        CaptureCallStacks = true,
        MaxClosureLogs = 2,
        MaxStackFrames = 8
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
            func = function() end,
            name = "ClosureSpyInternal",
            source = "@modules/ClosureSpy.lua",
            line = 100
        },
        {
            func = externalCaller,
            name = "ExternalCaller",
            source = "@game/ExternalCaller.lua",
            line = 42
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
assertEqual(#hook.Logs[1].stack, 1, "internal call-stack frame filtered")
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
assertEqual(originalCalls, 2, "blocked call skips original")
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
assertEqual(originalCalls, 3, "nil argument block skips original")
assertEqual(hook.Calls, 4, "argument-blocked call is captured")
assertEqual(hook.DroppedLogs, 2, "retention remains bounded")

assertEqual(hook:Remove(), true, "hook removal succeeds")
assertEqual(closure.Data, target, "closure target restored")

hook:Clear()
assertEqual(hook.Calls, 0, "clear resets call count")
assertEqual(hook.DroppedLogs, 0, "clear resets dropped count")
assertEqual(#hook.Logs, 0, "clear removes history")

print("closure_spec.lua: ok")
