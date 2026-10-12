local root = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\][^/\\]+$")) or ""

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local target = function() end
local closure = { Data = target }
local value, reads = "before", 0
_G.setConstant = function(subject, index, nextValue)
    equal(subject, target, "constant setter receives the closure function")
    equal(index, 2, "constant setter index")
    value = nextValue
end
_G.getConstant = function(subject, index)
    equal(subject, target, "constant getter receives the closure function")
    equal(index, 2, "constant getter index")
    return value
end
_G.setUpvalue = function(subject, index, nextValue)
    equal(subject, target, "upvalue setter receives the closure function")
    equal(index, 3, "upvalue setter index")
    value = nextValue
end
_G.getUpvalue = function(subject, index)
    equal(subject, target, "upvalue getter receives the closure function")
    equal(index, 3, "upvalue getter index")
    reads = reads + 1
    return value
end

local Constant = dofile(root .. "objects/Constant.lua")
local Upvalue = dofile(root .. "objects/Upvalue.lua")
local constant = Constant.new(closure, 2, "before")
constant:Set(false)
equal(constant.Value, false, "constant setter preserves false")
value = "external update"
constant:Update()
equal(constant.Value, value, "constant refresh reads the actual function")

local upvalue = Upvalue.new(closure, 3, "before")
upvalue:Update(false)
equal(upvalue.Value, false, "explicit false upvalue update")
upvalue:Update(nil)
equal(upvalue.Value, nil, "explicit nil upvalue update")
equal(reads, 0, "explicit updates do not reread the executor")
upvalue:Update()
equal(reads, 1, "omitted update value rereads the executor")
equal(upvalue.Value, value, "refresh reads current upvalue")
upvalue.Scanned = { changed = false, removed = true, retained = 1 }
upvalue:Update({ changed = true, retained = false, unscanned = 8 })
equal(upvalue.Scanned.changed, true, "scanned false entry refreshes")
equal(upvalue.Scanned.removed, nil, "removed scanned entry is released")
equal(upvalue.Scanned.retained, false, "scanned entry may become false")
equal(upvalue.Scanned.unscanned, nil, "refresh preserves the selected scan subset")
upvalue:Set(nil)
equal(upvalue.Value, nil, "setting nil preserves nil")
equal(upvalue.Scanned, nil, "setting a scalar clears stale table details")

_G.getInfo = function() return { name = "cached" } end
local Closure = dofile(root .. "objects/Closure.lua")
local liveModel = Closure.new(target)
equal(Closure.new(target), liveModel, "active closure models retain identity")
local weakModel = setmetatable({ liveModel }, { __mode = "v" })
liveModel = nil
collectgarbage("collect")
equal(weakModel[1], nil, "inactive closure models and environments are collectible")

-- Run the actual scanners against changing executor values and hostile tables.
local imported = { ["objects/Closure"] = Closure }
_G.import = function(path)
    if not imported[path] then imported[path] = dofile(root .. path .. ".lua") end
    return imported[path]
end
_G.typeof = type
local constants = { "alpha", "beta", false }
local upvalues = { "alpha", "beta", { hit = "alpha", miss = false } }
local constantReads = 0
_G.getLuaClosures = function() return { target, target } end
_G.getConstants = function()
    constantReads = constantReads + 1
    return constants
end
_G.getUpvalues = function() return upvalues end
local ConstantScanner = import("modules/ConstantScanner")
local UpvalueScanner = import("modules/UpvalueScanner")
local firstScan = ConstantScanner.Scan("alpha")
equal(firstScan[target].Constants[1].Value, "alpha", "constant query matches")
equal(constantReads, 1, "duplicate closure providers are inspected once")
local nextScan = ConstantScanner.Scan("beta")
equal(nextScan[target].Constants[1], nil, "new constant query clears stale matches")
equal(nextScan[target].Constants[2].Value, "beta", "new constant query retains matching values")
equal(ConstantScanner.Scan("false")[target].Constants[3].Value, false, "boolean constants are searchable")

local firstUpvalueScan = UpvalueScanner.Scan("alpha", true)
equal(firstUpvalueScan[target].Upvalues[3].Scanned.hit, "alpha", "deep scan matches table entries")
local nextUpvalueScan = UpvalueScanner.Scan("beta", true)
equal(nextUpvalueScan[target].Upvalues[1], nil, "new upvalue query clears stale scalar matches")
equal(nextUpvalueScan[target].Upvalues[3], nil, "new upvalue query clears stale table matches")
upvalues = { setmetatable({ hit = "alpha" }, { __pairs = function() error("unexpected __pairs") end }) }
equal(UpvalueScanner.Scan("alpha", true)[target].Upvalues[1].Scanned.hit, "alpha", "deep scan avoids game __pairs")

local shouldCancel = false
local waits = 0
_G.task = { wait = function() waits = waits + 1; shouldCancel = true end }
upvalues = { {} }
for index = 1, 200 do upvalues[1][index] = "alpha" end
local _, cancelled = UpvalueScanner.Scan("alpha", true, {
    YieldEvery = 16,
    IsCancelled = function() return shouldCancel end
})
equal(cancelled, true, "deep scans cancel inside large upvalue tables")
equal(waits, 1, "deep scans yield and stop after cancellation")
print("value_model_spec.lua: ok")
