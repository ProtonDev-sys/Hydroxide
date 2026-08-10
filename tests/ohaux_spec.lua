local root = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\][^/\\]+$")) or ""
assert(root, "unable to locate repository root")

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
    end
end

local named = function() end
local anonymous = function() end
local legacy = function() end
local info = {
    [named] = { name = "target", nups = 2 },
    [anonymous] = { name = "", nups = 1 },
    [legacy] = { name = "legacy" }
}
local constants = {
    [named] = { [1] = "needle", [2] = 42 },
    [anonymous] = { [1] = "anonymous" },
    [legacy] = { [1] = "legacy" }
}

_G.newproxy = function()
    return {}
end
_G.getgc = function()
    return { anonymous, legacy, named }
end
_G.filtergc = nil
_G.isexecutorclosure = function()
    return false
end
_G.islclosure = function(value)
    return type(value) == "function"
end
_G.getfenv = nil
_G.typeof = _G.typeof or type
debug.getinfo = function(closure)
    return info[closure]
end
debug.getupvalue = function(closure, index)
    local closureInfo = info[closure]

    if closure == legacy then
        return index == 1 and "legacy-value" or nil
    end

    if not closureInfo or index < 1 or index > closureInfo.nups then
        error("invalid upvalue index")
    end

    return index == 1 and "first" or "second"
end
debug.getconstants = function(closure)
    return constants[closure]
end

local aux = dofile(root .. "ohaux.lua")

assertEqual(aux.searchClosure(nil, "target", 2, { [1] = "needle" }), named, "named closure match")
assertEqual(aux.searchClosure(nil, "target", 3, { [1] = "needle" }), nil, "out-of-range upvalue rejected")
assertEqual(aux.searchClosure(nil, "target", 2, { [1] = "wrong" }), nil, "constant mismatch rejected")
assertEqual(aux.searchClosure(nil, "Unnamed function", 1, { [1] = "anonymous" }), anonymous, "anonymous match")
assertEqual(aux.searchClosure(nil, "legacy", 1, { [1] = "legacy" }), legacy, "legacy non-nil fallback")
assertEqual(aux.searchClosure(nil, "legacy", 99, { [1] = "legacy" }), nil, "legacy nil fallback rejects bad index")

print("ohaux_spec.lua: ok")
