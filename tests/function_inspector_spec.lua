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

print("function_inspector_spec.lua: ok")
