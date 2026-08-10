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
        end
    })
end

local gameObject = makeObject({
    __type = "DataModel",
    Name = "game",
    Services = {}
}, "game")

function gameObject:GetService(name)
    return self.Services[name]
end

local playersService = makeObject({
    __type = "Players",
    Name = "Players",
    ClassName = "Players",
    Parent = gameObject
}, "Players")

local workspaceObject = makeObject({
    __type = "Workspace",
    Name = "Workspace",
    ClassName = "Workspace",
    Parent = gameObject
}, "Workspace")

local localPlayer = makeObject({
    __type = "Player",
    Name = "LocalPlayer",
    ClassName = "Player",
    Parent = playersService
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
        name = "spec"
    }
end

_G.buffer = {
    tostring = function(value)
        return value.bytes
    end,
    fromstring = function(bytes)
        return makeObject({
            __type = "buffer",
            bytes = bytes
        }, "buffer")
    end
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

local numberRange = makeObject({
    __type = "NumberRange",
    Min = 1,
    Max = 25
}, "1 25")

local dateTime = makeObject({
    __type = "DateTime",
    UnixTimestampMillis = 1700000000123
}, "DateTime.now()")

local destroyedInstance = makeObject({
    __type = "Instance",
    Name = "Ghost",
    ClassName = "Folder",
    Parent = nil
}, "Ghost")

local fakeBuffer = makeObject({
    __type = "buffer",
    bytes = "A\0B"
}, "buffer")

local cyclic = {}
cyclic.self = cyclic

assertEqual(userdataValue(numberRange), "NumberRange.new(1, 25)", "NumberRange serialization")
assertEqual(
    userdataValue(dateTime),
    "DateTime.fromUnixTimestampMillis(" .. tostring(dateTime.UnixTimestampMillis) .. ")",
    "DateTime serialization"
)
assertEqual(dataToString(fakeBuffer), 'buffer.fromstring("A\\0B")', "buffer serialization")
assertEqual(toUnicode(string.char(0xC3, 0xA9)), "utf8.char(233)", "unicode serialization")
assertEqual(getInstancePath(destroyedInstance), '.Ghost --[[ PARENTED TO NIL OR DESTROYED ]]', "destroyed instance path")
assertContains(tableToString(cyclic), "OH_CYCLIC_PROTECTION", "cyclic table protection")
assertEqual(#summarizeValue(string.rep("x", 200), 48) <= 48, true, "string preview is bounded")
assertContains(summarizeValue({ one = 1, two = 2 }), "2 entries", "table preview avoids full serialization")
assertEqual(summarizeValue(nil), "nil", "nil preview")

print("serializer_spec.lua: ok")
