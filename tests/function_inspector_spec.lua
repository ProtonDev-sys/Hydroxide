local root = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\][^/\\]+$")) or ""
assert(root, "unable to locate repository root")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function sourceFrom(description)
	return description:match("%-%- Decompiled source\n(.*)")
end

_G.getInfo = function()
	return {
		name = "inspected",
		what = "Lua",
		source = "@function_inspector_spec.lua",
		short_src = "function_inspector_spec.lua",
		linedefined = 1,
		currentline = 1,
		nups = 0,
	}
end
_G.getUpvalues = function()
	return {}
end
_G.getConstants = function()
	return {}
end
_G.getProtos = function()
	return {}
end

local decompileCalls = 0
_G.decompile = function()
	decompileCalls = decompileCalls + 1
	return string.rep("x", 4096)
end

local FunctionInspector = dofile(root .. "ui/controls/FunctionInspector.lua")
local target = function() end
local first = FunctionInspector.DescribeFunction(target, {
	MaxOutputBytes = 16384,
	MaxSourceBytes = 2048,
})
local firstSource = assert(sourceFrom(first), "first inspection should include source")
assertEqual(#firstSource, 2048, "first function source obeys its byte limit")
assert(firstSource:find("source truncated", 1, true), "first source reports truncation")

local smaller = FunctionInspector.DescribeFunction(target, {
	MaxOutputBytes = 16384,
	MaxSourceBytes = 1024,
})
local smallerSource = assert(sourceFrom(smaller), "smaller inspection should include source")
assertEqual(#smallerSource, 1024, "cached function source is rebound to a smaller limit")
assertEqual(decompileCalls, 1, "smaller function source requests reuse the cache")

FunctionInspector.DescribeFunction(target, {
	MaxOutputBytes = 16384,
	MaxSourceBytes = 3072,
})
assertEqual(decompileCalls, 2, "larger function source requests refresh a truncated cache")

local cancelled = FunctionInspector.DescribeFunction(function() end, {
	IsAlive = function()
		return false
	end,
})
assertEqual(cancelled, "Function inspection was cancelled.", "cancelled inspection returns promptly")
assertEqual(decompileCalls, 2, "cancelled inspection never invokes the decompiler")

local hugeKey = string.rep("k", 1024 * 1024)
local hugeValue = string.rep("v", 1024 * 1024)
_G.getConstants = function()
	return { [hugeKey] = hugeValue }
end
local boundedValues = FunctionInspector.DescribeFunction(function() end, {
	IncludeSource = false,
	MaxOutputBytes = 4096,
})
assert(#boundedValues <= 4096, "huge inspector keys and values remain inside the output budget")
assert(not boundedValues:find(string.rep("k", 300), 1, true), "huge inspector keys are preview-bounded")
assert(not boundedValues:find(string.rep("v", 300), 1, true), "huge inspector values are preview-bounded")

_G.getConstants = function()
	return {}
end
local cachedFunctions = {}
local callsBeforeCacheFill = decompileCalls

for index = 1, 65 do
	cachedFunctions[index] = function() return index end
	FunctionInspector.DescribeFunction(cachedFunctions[index], {
		MaxOutputBytes = 4096,
		MaxSourceBytes = 1024,
	})
end

assertEqual(decompileCalls, callsBeforeCacheFill + 65, "function inspector caches each new source once")
FunctionInspector.DescribeFunction(cachedFunctions[1], {
	MaxOutputBytes = 4096,
	MaxSourceBytes = 1024,
})
assertEqual(decompileCalls, callsBeforeCacheFill + 66, "function inspector evicts its oldest bounded cache entry")

_G.isLClosure = function() return false end
_G.isXClosure = function() return false end
local cFunction = FunctionInspector.DescribeFunction(function() end, { IncludeSource = false })
assert(cFunction:find("Closure type: C", 1, true), "false closure predicate still identifies C functions")
assert(cFunction:find("Origin: game", 1, true), "false executor predicate still identifies game functions")

local largeValues = {}
for index = 1, 100 do
	largeValues[index] = string.rep("value", 80)
end
_G.getConstants = function() return largeValues end

for _, maximum in ipairs({ 1, 32, 256, 1024, 4096 }) do
	local description = FunctionInspector.DescribeFunction(function() end, {
		IncludeSource = false,
		MaxValues = 100,
		MaxOutputBytes = maximum,
	})
	assert(#description <= maximum, "function output including truncation marker obeys an explicit byte budget")
end

local visitedFrames = 0
local stack = {}
for index = 1, 1000 do
	stack[index] = setmetatable({}, {
		__index = function(_, key)
			visitedFrames = visitedFrames + 1
			if key == "name" then return "frame" end
			if key == "source" then return "@source.lua" end
		end,
	})
end
local stackOutput = FunctionInspector.DescribeStack(stack, { MaxOutputBytes = 512 })
assert(#stackOutput <= 512, "stack output obeys an explicit byte budget")
assert(visitedFrames < 200, "stack summary stops visiting frames once the output is full")

local function cacheBudget(name)
	local budget = { Released = 0, Reserved = 0 }
	function budget:Reserve()
		self.Reserved = self.Reserved + 1
		return { Owner = name }
	end
	function budget:Release(token)
		assertEqual(token.Owner, name, "source cache token is released to its original budget")
		self.Released = self.Released + 1
	end
	return budget
end
local firstBudget, nextBudget = cacheBudget("first"), cacheBudget("next")
_G.oh = { Settings = { MaxFunctionSourceCacheEntries = 1 }, FunctionSourceCache = firstBudget }
_G.getConstants = function() return {} end
local scopedInspector = dofile(root .. "ui/controls/FunctionInspector.lua")
scopedInspector.DescribeFunction(function() end, { MaxSourceBytes = 1024 })
_G.oh.FunctionSourceCache = nextBudget
scopedInspector.DescribeFunction(function() end, { MaxSourceBytes = 1024 })
assertEqual(firstBudget.Released, 1, "changing the runtime budget does not leak old source reservations")
assertEqual(nextBudget.Released, 0, "old source entries never release a new runtime's budget tokens")

local exitedBudget, replacementBudget = cacheBudget("exited"), cacheBudget("replacement")
local owner = { Settings = {}, FunctionSourceCache = exitedBudget }
local environment = setmetatable({ oh = owner }, { __index = _G })
local exitingInspector = assert(loadfile(root .. "ui/controls/FunctionInspector.lua", "t", environment))()
local exitDecompileCalls = 0
_G.decompile = function()
	exitDecompileCalls = exitDecompileCalls + 1
	owner.Exited = true
	_G.oh = { Settings = {}, FunctionSourceCache = replacementBudget }
	return "-- late source from the previous runtime"
end
local lateDescription = exitingInspector.DescribeFunction(function() end)
assert(not sourceFrom(lateDescription), "inspection finishing after shutdown cannot publish late source")
assertEqual(exitedBudget.Reserved, 0, "shutdown prevents late source from repopulating its cleared cache budget")
assertEqual(replacementBudget.Reserved, 0, "late source never reserves a replacement runtime's cache budget")
assertEqual(exitingInspector.DescribeFunction(function() end), "Function inspection was cancelled.",
	"an inspector belonging to an exited runtime remains cancelled after replacement")
assertEqual(exitDecompileCalls, 1, "an exited inspector never starts another decompile")

print("function_inspector_spec.lua: ok")
