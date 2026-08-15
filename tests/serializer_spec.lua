local root = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\][^/\\]+$")) or ""
assert(root, "unable to locate repository root")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function assertContains(haystack, needle, label)
	if not haystack:find(needle, 1, true) then
		error(("%s: expected to find %s in %s"):format(label, needle, haystack), 2)
	end
end

local function makeObject(fields, stringValue)
	return setmetatable(fields, {
		__tostring = function()
			return stringValue or fields.Name or fields.__type or "object"
		end,
	})
end

local gameObject = makeObject({
	__type = "DataModel",
	Name = "game",
	Services = {},
}, "game")

function gameObject:GetService(name)
	return self.Services[name]
end

local playersService = makeObject({
	__type = "Players",
	Name = "Players",
	ClassName = "Players",
	Parent = gameObject,
}, "Players")

local workspaceObject = makeObject({
	__type = "Workspace",
	Name = "Workspace",
	ClassName = "Workspace",
	Parent = gameObject,
}, "Workspace")

local localPlayer = makeObject({
	__type = "Player",
	Name = "LocalPlayer",
	ClassName = "Player",
	Parent = playersService,
}, "LocalPlayer")

playersService.LocalPlayer = localPlayer
gameObject.Services.Players = playersService
gameObject.Services.Workspace = workspaceObject

_G.game = gameObject
_G.workspace = workspaceObject

_G.typeof = function(value)
	if type(value) == "table" and rawget(value, "__type") then
		return rawget(value, "__type")
	end

	return type(value)
end

_G.getMetatable = getmetatable
_G.getInfo = function(_)
	return {
		name = "spec",
	}
end

_G.buffer = {
	len = function(value)
		return #value.bytes
	end,
	tostring = function(value)
		return value.bytes
	end,
	fromstring = function(bytes)
		return makeObject({
			__type = "buffer",
			bytes = bytes,
		}, "buffer")
	end,
}

local stringMethods = dofile(root .. "methods/string.lua")
for name, method in pairs(stringMethods) do
	_G[name] = method
end

local tableMethods = dofile(root .. "methods/table.lua")
for name, method in pairs(tableMethods) do
	_G[name] = method
end

local userdataMethods = dofile(root .. "methods/userdata.lua")
for name, method in pairs(userdataMethods) do
	_G[name] = method
end

_G.oh = {
	Settings = {},
}

local scriptBuilderMethods = dofile(root .. "methods/scriptbuilder.lua")
for name, method in pairs(scriptBuilderMethods) do
	_G[name] = method
end

local numberRange = makeObject({
	__type = "NumberRange",
	Min = 1,
	Max = 25,
}, "1 25")

local dateTime = makeObject({
	__type = "DateTime",
	UnixTimestampMillis = 1700000000123,
}, "DateTime.now()")

local destroyedInstance = makeObject({
	__type = "Instance",
	Name = "Ghost",
	ClassName = "Folder",
	Parent = nil,
}, "Ghost")

local specialChild = makeObject({
	__type = "Instance",
	Name = 'end"\\\n' .. string.char(0xC3, 0xA9),
	ClassName = "Folder",
	Parent = workspaceObject,
}, "SpecialChild")

local pathWaypoint = makeObject({
	__type = "PathWaypoint",
	Position = makeObject({
		__type = "Vector3",
		X = 1,
		Y = 2,
		Z = 3,
	}, "1, 2, 3"),
	Action = "Enum.PathWaypointAction.Walk",
	Label = 'a"b',
}, "PathWaypoint")

local fakeBuffer = makeObject({
	__type = "buffer",
	bytes = "A\0B",
}, "buffer")

local cyclic = {}
cyclic.self = cyclic
local nested = {
	first = cyclic,
	alsoFirst = cyclic,
}

local remoteEvent = makeObject({
	__type = "Instance",
	Name = "Probe Remote",
	ClassName = "RemoteEvent",
	Parent = workspaceObject,
}, "Probe Remote")

assertEqual(userdataValue(numberRange), "NumberRange.new(1, 25)", "NumberRange serialization")
assertEqual(
	userdataValue(dateTime),
	"DateTime.fromUnixTimestampMillis(" .. tostring(dateTime.UnixTimestampMillis) .. ")",
	"DateTime serialization"
)
assertEqual(dataToString(fakeBuffer), 'buffer.fromstring("A\\000B")', "buffer serialization")
_G.oh.Settings.MaxGeneratedBufferBytes = 2
assertContains(dataToString(fakeBuffer), "buffer exceeds configured byte limit", "legacy buffer size guard")
_G.oh.Settings.MaxGeneratedBufferBytes = 65536
local unreadableBuffer = makeObject({ __type = "buffer" }, "unreadable buffer")
assertContains(dataToString(unreadableBuffer), "unreadable buffer", "failed buffer read never fabricates empty data")
local originalBufferToString = _G.buffer.tostring
_G.buffer.tostring = function()
	return nil
end
assertContains(dataToString(fakeBuffer), "unreadable buffer", "non-string buffer serialization is rejected")
_G.buffer.tostring = function()
	return "wrong length"
end
assertContains(dataToString(fakeBuffer), "unreadable buffer", "mismatched buffer serialization is rejected")
_G.buffer.tostring = originalBufferToString
assertEqual(toUnicode(string.char(0xC3, 0xA9)), "utf8.char(233)", "unicode serialization")
assertEqual(
	getInstancePath(destroyedInstance),
	"nil --[[ Detached or destroyed Instance: Ghost ]]",
	"destroyed instance path is valid code"
)
assertContains(
	getInstancePath(specialChild),
	'game:GetService("Workspace")["end\\"\\\\\\n\\195\\169"]',
	"safe path quoting"
)
assertContains(userdataValue(pathWaypoint), '"a\\"b"', "PathWaypoint label quoting")
assertEqual(dataToString(math.huge), "math.huge", "positive infinity serialization")
assertEqual(dataToString(-math.huge), "-math.huge", "negative infinity serialization")
assertEqual(dataToString(0 / 0), "(0 / 0)", "NaN serialization")

local binaryString = 'A"\\\0\n' .. string.char(0xFF)
local binaryChunk = assert(load("return " .. dataToString(binaryString)))
assertEqual(binaryChunk(), binaryString, "binary-safe string serialization")
assertContains(tableToString(cyclic), "OH_CYCLIC_PROTECTION", "cyclic table protection")
local expandedTree = formatValueTree(nested, {
	MaxDepth = 8,
	MaxEntries = 32,
	MaxTableEntries = 32,
	MaxOutputBytes = 4096,
})
assertContains(expandedTree, "table#1 {", "expanded value view labels the root table")
assertContains(expandedTree, '["first"] = ', "expanded value view shows table keys")
assertContains(expandedTree, '["self"] = <ref table#', "expanded value view exposes cycles safely")
assertContains(expandedTree, '["alsoFirst"] = ', "expanded value view shows shared-table fields")

local boundedTree = formatValueTree({ one = 1, two = 2, three = 3 }, {
	MaxEntries = 1,
	MaxTableEntries = 1,
	MaxOutputBytes = 512,
})
assertContains(boundedTree, "entry limit reached", "expanded value view reports bounded truncation")

local hostileView = setmetatable({ safe = { nested = true } }, {
	__pairs = function()
		error("formatValueTree must not invoke __pairs")
	end,
})
assertContains(formatValueTree(hostileView), '["safe"]', "expanded value view uses raw iteration")
assertEqual(#summarizeValue(string.rep("x", 200), 48) <= 48, true, "string preview is bounded")
assertContains(summarizeValue({ one = 1, two = 2 }), "2 entries", "table preview avoids full serialization")
assertEqual(summarizeValue(nil), "nil", "nil preview")

local generatedRemoteScript = buildRemoteScript(remoteEvent, "FireServer", {
	"alpha",
	nil,
	nested,
	n = 3,
}, {
	method = "FireServer",
	timestamp = 123.5,
	script = remoteEvent,
})

assertContains(
	generatedRemoteScript,
	'local OH_Remote = game:GetService("Workspace")["Probe Remote"]',
	"remote path emitted"
)
assertContains(generatedRemoteScript, "OH_Args.n = 3", "nil argument count preserved")
assertContains(generatedRemoteScript, "OH_Args[2] = nil", "nil argument emitted")
assertContains(generatedRemoteScript, 'OH_Table_2["self"] = OH_Table_2', "cyclic table rebuilt")
assertContains(generatedRemoteScript, 'OH_Table_1["first"] = OH_Table_2', "shared table reference rebuilt")
assertContains(
	generatedRemoteScript,
	"return OH_Remote:FireServer(OH_Unpack(OH_Args, 1, OH_Args.n))",
	"remote replay call emitted"
)

print("serializer_spec.lua: ok")
