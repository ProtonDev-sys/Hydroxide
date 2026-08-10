local Remote = {}

local DEFAULT_MAX_LOGS = 500

local function createLogBuffer(capacity)
    local storage = {}
    local head = 1
    local count = 0
    local methods = {}
    local proxy = {}

    local function physicalIndex(logicalIndex)
        return ((head + logicalIndex - 2) % capacity) + 1
    end

    function methods.Push(_, value)
        if count < capacity then
            count = count + 1
            storage[physicalIndex(count)] = value
            return nil
        end

        local dropped = storage[head]
        storage[head] = value
        head = (head % capacity) + 1
        return dropped
    end

    function methods.Remove(_, target)
        local found

        for logicalIndex = 1, count do
            if storage[physicalIndex(logicalIndex)] == target then
                found = logicalIndex
                break
            end
        end

        if not found then
            return false
        end

        for logicalIndex = found, count - 1 do
            storage[physicalIndex(logicalIndex)] = storage[physicalIndex(logicalIndex + 1)]
        end

        storage[physicalIndex(count)] = nil
        count = count - 1

        if count == 0 then
            head = 1
        end

        return true
    end

    function methods.Clear()
        storage = {}
        head = 1
        count = 0
    end

    local function iterate()
        local logicalIndex = 0

        return function()
            logicalIndex = logicalIndex + 1

            if logicalIndex <= count then
                return logicalIndex, storage[physicalIndex(logicalIndex)]
            end
        end
    end

    return setmetatable(proxy, {
        __len = function()
            return count
        end,
        __index = function(_, key)
            if type(key) == "number" and key >= 1 and key <= count and key % 1 == 0 then
                return storage[physicalIndex(key)]
            end

            return methods[key]
        end,
        __iter = iterate,
        __pairs = iterate
    })
end

local function normalizeMaxLogs(value)
    value = tonumber(value)

    if not value then
        return DEFAULT_MAX_LOGS
    end

    return math.max(1, math.floor(value))
end

local function argumentCount(args)
    if type(args.n) == "number" then
        return math.max(0, math.floor(args.n))
    end

    return #args
end

function Remote.new(instance, maxLogs)
    local remote = {}

    remote.Instance = instance
    remote.MaxLogs = normalizeMaxLogs(maxLogs)
    remote.Logs = createLogBuffer(remote.MaxLogs)
    remote.Calls = 0
    remote.TotalCalls = 0
    remote.DroppedCalls = 0
    remote.Blocked = false
    remote.Ignored = false
    remote.Clear = Remote.clear
    remote.Block = Remote.block
    remote.Unblock = Remote.unblock
    remote.SetBlocked = Remote.setBlocked
    remote.Ignore = Remote.ignore
    remote.Unignore = Remote.unignore
    remote.SetIgnored = Remote.setIgnored
    remote.BlockedArgs = {}
    remote.IgnoredArgs = {}
    remote.BlockArg = Remote.blockArg
    remote.IgnoreArg = Remote.ignoreArg
    remote.AreArgsBlocked = Remote.areArgsBlocked
    remote.AreArgsIgnored = Remote.areArgsIgnored
    remote.IncrementCalls = Remote.incrementCalls
    remote.DecrementCalls = Remote.decrementCalls

    return remote
end

function Remote.clear(remote)
    remote.Calls = 0
    remote.TotalCalls = 0
    remote.DroppedCalls = 0
    remote.Logs:Clear()
end

function Remote.setBlocked(remote, blocked)
    remote.Blocked = blocked and true or false
end

function Remote.block(remote)
    remote:SetBlocked(not remote.Blocked)
end

function Remote.unblock(remote)
    remote:SetBlocked(false)
end

function Remote.setIgnored(remote, ignored)
    remote.Ignored = ignored and true or false
end

function Remote.ignore(remote)
    remote:SetIgnored(not remote.Ignored)
end

function Remote.unignore(remote)
    remote:SetIgnored(false)
end

function Remote.blockArg(remote, index, value, byType)
    local blockedArgs = remote.BlockedArgs
    local blockedIndex = blockedArgs[index]

    if not blockedIndex then
        blockedIndex = {
            types = {},
            values = {}
        }
        blockedArgs[index] = blockedIndex
    end

    if byType then
        blockedIndex.types[value] = true
    else
        blockedIndex.values[value] = true
    end
end

function Remote.ignoreArg(remote, index, value, byType)
    local ignoredArgs = remote.IgnoredArgs
    local ignoredIndex = ignoredArgs[index]

    if not ignoredIndex then
        ignoredIndex = {
            types = {},
            values = {}
        }

        ignoredArgs[index] = ignoredIndex
    end

    if byType then
        ignoredIndex.types[value] = true
    else
        ignoredIndex.values[value] = true
    end
end

function Remote.areArgsBlocked(remote, args)
    local blockedArgs = remote.BlockedArgs

    for index = 1, argumentCount(args) do
        local value = args[index]
        local indexBlock = blockedArgs[index]

        if indexBlock
            and (indexBlock.types[typeof(value)] or (value ~= nil and indexBlock.values[value] ~= nil))
        then
            return true
        end
    end

    return false
end

function Remote.areArgsIgnored(remote, args)
    local ignoredArgs = remote.IgnoredArgs

    for index = 1, argumentCount(args) do
        local value = args[index]
        local indexIgnore = ignoredArgs[index]

        if indexIgnore
            and (indexIgnore.types[typeof(value)] or (value ~= nil and indexIgnore.values[value] ~= nil))
        then
            return true
        end
    end

    return false
end

function Remote.incrementCalls(remote, call)
    local logs = remote.Logs
    local dropped = false

    remote.Calls = remote.Calls + 1
    remote.TotalCalls = remote.TotalCalls + 1
    local droppedCall = logs:Push(call)

    if droppedCall ~= nil then
        remote.DroppedCalls = remote.DroppedCalls + 1
        dropped = true
    end

    return dropped
end

function Remote.decrementCalls(remote, call)
    local logs = remote.Logs
    if logs:Remove(call) then
        remote.Calls = math.max(0, remote.Calls - 1)
    end
end

return Remote
