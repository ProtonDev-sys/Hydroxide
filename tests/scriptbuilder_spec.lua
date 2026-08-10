local root = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\][^/\\]+$")) or ""
assert(root, "unable to locate repository root")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function assertContains(haystack, needle, label)
	if not haystack:find(needle, 1, true) then
		error(("%s: expected to find %s"):format(label, needle), 2)
	end
end

local function assertNotContains(haystack, needle, label)
	if haystack:find(needle, 1, true) then
		error(("%s: did not expect to find %s"):format(label, needle), 2)
	end
end

local pack = table.pack or function(...)
	return { n = select("#", ...), ... }
end

table.create = table.create or function()
	return {}
end

local function makeInstance(className, name, parent)
	local instance = {
		__type = "Instance",
		ClassName = className,
		Name = name,
		Parent = parent,
	}

	if parent then
		parent[name] = instance
	end

	return instance
end

local gameObject = {
	__type = "DataModel",
	Name = "game",
	Services = {},
}

function gameObject:GetService(name)
	return self.Services[name]
end

local replicatedStorage = makeInstance("ReplicatedStorage", "ReplicatedStorage", gameObject)
gameObject.Services.ReplicatedStorage = replicatedStorage

local remote = makeInstance("RemoteFunction", "Replay", replicatedStorage)
local captured

function remote:FireServer(...)
	captured = pack(...)
	return "fire-result"
end

function remote:InvokeServer(...)
	captured = pack(...)
	return "invoke-result", nil, captured.n
end

_G.game = gameObject
_G.oh = { Settings = {} }
_G.typeof = function(value)
	return type(value) == "table" and rawget(value, "__type") or type(value)
end
_G.buffer = {
	tostring = function(value)
		return value.bytes
	end,
	fromstring = function(bytes)
		return { __type = "buffer", bytes = bytes }
	end,
}

local builder = dofile(root .. "methods/scriptbuilder.lua")

local function compileAndRun(source)
	local chunk, compileError = load(source, "generated-replay", "t", _G)
	assert(chunk, compileError)
	return pack(chunk())
end

local shared = { ["end"] = 7 }
shared.self = shared
shared.unsupportedValue = function() end
shared[function() end] = "function-key"
shared[coroutine.create(function() end)] = "thread-key"

local args = {
	n = 4,
	[2] = shared,
	[3] = shared,
	[4] = "tail",
}
local source = assert(builder.buildRemoteScript(remote, "InvokeServer", args, {
	timestamp = 1700000000.125,
}))

assertNotContains(source, ".end", "reserved key uses bracket syntax")
assertNotContains(source, "[nil", "unsupported keys are omitted")
assertContains(source, "Warning:", "lossy values are disclosed")

local invocation = compileAndRun(source)
assertEqual(invocation[1], "invoke-result", "InvokeServer first return")
assertEqual(invocation[2], nil, "InvokeServer nil return")
assertEqual(invocation[3], 4, "InvokeServer trailing return")
assertEqual(invocation.n, 3, "InvokeServer packed return count")
assertEqual(captured.n, 4, "packed argument count")
assertEqual(captured[1], nil, "leading nil argument")
assertEqual(captured[2], captured[3], "shared table identity")
assertEqual(captured[2].self, captured[2], "cyclic table identity")
assertEqual(captured[2]["end"], 7, "reserved table key")

local specialString = 'quote" slash\\ nul\0 newline\n utf8:' .. string.char(0xC3, 0xA9, 0xFF)
local numberArgs = {
	n = 5,
	[1] = math.huge,
	[2] = -math.huge,
	[3] = 0 / 0,
	[4] = specialString,
	[5] = false,
}

compileAndRun(assert(builder.buildRemoteScript(remote, "FireServer", numberArgs)))
assertEqual(captured[1], math.huge, "positive infinity")
assertEqual(captured[2], -math.huge, "negative infinity")
assertEqual(captured[3] ~= captured[3], true, "NaN")
assertEqual(captured[4], specialString, "binary-safe string")
assertEqual(captured[5], false, "boolean argument")

local specialName = 'end"\\\n' .. string.char(0xC3, 0xA9)
local specialRemote = makeInstance("RemoteEvent", specialName, replicatedStorage)

function specialRemote:FireServer(...)
	captured = pack(...)
end

local callingScript = makeInstance("LocalScript", "caller\n]]\nerror('injected')", replicatedStorage)
local metadataSource = assert(builder.buildRemoteScript(specialRemote, "FireServer", { n = 0 }, {
	timestamp = "1700\nerror('injected') --[[ ]]",
	script = callingScript,
}))

assertNotContains(metadataSource, "\nerror('injected')", "metadata is confined to comments")
compileAndRun(metadataSource)
assertEqual(captured.n, 0, "special Instance path executes")

local rejected, rejectError = builder.buildRemoteScript(remote, "FireServer\nerror('injected')", { n = 0 })
assertEqual(rejected, nil, "unknown method rejected")
assertContains(rejectError, "Unsupported remote method", "unknown method error")

local detached = makeInstance("RemoteEvent", "Detached", nil)
local detachedSource, detachedError = builder.buildRemoteScript(detached, "FireServer", { n = 0 })
assertEqual(detachedSource, nil, "detached remote rejected")
assertContains(detachedError, "detached or destroyed", "detached remote error")

_G.oh.Settings.MaxGeneratedTableEntries = 8
_G.oh.Settings.MaxGeneratedTableDepth = 1
_G.oh.Settings.MaxGeneratedTables = 8
_G.oh.Settings.MaxGeneratedStringBytes = 256
_G.oh.Settings.MaxGeneratedBufferBytes = 256

local wide = {}

for index = 1, 20 do
	wide[index] = index
end

local deep = { child = { child = { child = true } } }
local hostilePairs = setmetatable({ safe = true }, {
	__pairs = function()
		error("__pairs must not run")
	end,
})
local limitedSource = assert(builder.buildRemoteScript(remote, "FireServer", {
	n = 5,
	wide,
	deep,
	hostilePairs,
	string.rep("s", 300),
	{ __type = "buffer", bytes = string.rep("b", 300) },
}))

assertContains(limitedSource, "truncated after 8 entries", "entry limit warning")
assertContains(limitedSource, "depth limit", "depth limit warning")
assertContains(limitedSource, "string exceeds", "string limit warning")
assertContains(limitedSource, "buffer exceeds", "buffer limit warning")
compileAndRun(limitedSource)
assertEqual(captured[3].safe, true, "raw next bypasses hostile __pairs")
assertEqual(captured[4], nil, "oversized string becomes nil")
assertEqual(captured[5], nil, "oversized buffer becomes nil")

print("scriptbuilder_spec.lua: ok")
