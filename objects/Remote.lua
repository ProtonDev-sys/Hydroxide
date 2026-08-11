local Remote = {}

local DEFAULT_MAX_LOGS = 500
local DEFAULT_MAX_HISTORY_BYTES = 16777216

local function createLogBuffer(capacity, byteCapacity)
    local storage = {}
    local sizes = {}
    local head = 1
    local count = 0
    local storedBytes = 0
    local methods = {}
    local proxy = {}

    local function physicalIndex(logicalIndex)
        return ((head + logicalIndex - 2) % capacity) + 1
    end

    local function valueBytes(value)
        return math.max(0, math.floor(tonumber(type(value) == "table" and value.capturedBytes) or 0))
    end

    local function popOldest()
        if count == 0 then
            return nil
        end

        local dropped = storage[head]
        storedBytes = math.max(0, storedBytes - (sizes[head] or 0))
        storage[head] = nil
        sizes[head] = nil
        head = (head % capacity) + 1
        count = count - 1

        if count == 0 then
            head = 1
        end

        return dropped
    end

    function methods.Push(_, value)
        local bytes = valueBytes(value)
        local dropped = 0

        while count > 0 and (count >= capacity or storedBytes + bytes > byteCapacity) do
            popOldest()
            dropped = dropped + 1
        end

        count = count + 1
        local index = physicalIndex(count)
        storage[index] = value
        sizes[index] = bytes
        storedBytes = storedBytes + bytes
        return dropped
    end

    function methods.RefreshBytes(_, target)
        local found

        for logicalIndex = 1, count do
            if storage[physicalIndex(logicalIndex)] == target then
                found = physicalIndex(logicalIndex)
                break
            end
        end

        if not found then
            return 0
        end

        local nextBytes = valueBytes(target)
        storedBytes = math.max(0, storedBytes - (sizes[found] or 0)) + nextBytes
        sizes[found] = nextBytes

        local dropped = 0

        while count > 1 and storedBytes > byteCapacity do
            popOldest()
            dropped = dropped + 1
        end

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

        storedBytes = math.max(0, storedBytes - (sizes[physicalIndex(found)] or 0))

        for logicalIndex = found, count - 1 do
            local index = physicalIndex(logicalIndex)
            local nextIndex = physicalIndex(logicalIndex + 1)
            storage[index] = storage[nextIndex]
            sizes[index] = sizes[nextIndex]
        end

        local lastIndex = physicalIndex(count)
        storage[lastIndex] = nil
        sizes[lastIndex] = nil
        count = count - 1

        if count == 0 then
            head = 1
        end

        return true
    end

    function methods.Clear()
        storage = {}
        sizes = {}
        head = 1
        count = 0
        storedBytes = 0
    end

    function methods.Bytes()
        return storedBytes
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

local function normalizeMaxHistoryBytes(value)
    value = tonumber(value)

    if not value then
        return DEFAULT_MAX_HISTORY_BYTES
    end

    return math.max(1, math.floor(value))
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

local function normalizeArgumentIndex(index)
    index = tonumber(index)

    if not index or index ~= index or index == math.huge or index == -math.huge or index < 1 or index % 1 ~= 0 then
        return nil
    end

    return index
end

local function isNaN(value)
    return type(value) == "number" and value ~= value
end

local function buffersEqual(left, right)
    if left == right then
        return true
    elseif typeof(left) ~= "buffer" or typeof(right) ~= "buffer" or not buffer then
        return false
    elseif type(buffer.len) ~= "function" or type(buffer.readu8) ~= "function" then
        return false
    end

    local maximum = 4096

    if oh and oh.Settings then
        maximum = tonumber(oh.Settings.MaxConditionBufferBytes or oh.Settings.maxConditionBufferBytes) or maximum
    end

    local ran, matches = pcall(function()
        local leftLength = buffer.len(left)
        local rightLength = buffer.len(right)

        if leftLength ~= rightLength or leftLength > maximum then
            return false
        end

        for offset = 0, leftLength - 1 do
            if buffer.readu8(left, offset) ~= buffer.readu8(right, offset) then
                return false
            end
        end

        return true
    end)

    return ran and matches == true
end

local function addArgCondition(storage, index, value, byType)
    index = normalizeArgumentIndex(index)

    if not index then
        return false, "Argument index must be a positive integer"
    end

    local condition = storage[index]

    if not condition then
        condition = {
            types = {},
            values = {},
            nan = false
        }
        storage[index] = condition
    end

    if byType or value == nil then
        local valueType = byType and value or "nil"

        if type(valueType) ~= "string" or valueType == "" then
            return false, "Condition type must be a non-empty string"
        elseif condition.types[valueType] then
            return false, "Condition already exists"
        end

        condition.types[valueType] = true
    elseif isNaN(value) then
        if condition.nan then
            return false, "Condition already exists"
        end

        condition.nan = true
    else
        if typeof(value) == "buffer" then
            for expected in pairs(condition.values) do
                if typeof(expected) == "buffer" and buffersEqual(expected, value) then
                    return false, "Condition already exists"
                end
            end
        end

        if condition.values[value] ~= nil then
            return false, "Condition already exists"
        end

        condition.values[value] = true
    end

    return true
end

local function matchesValues(condition, value)
    if value == nil then
        return false
    elseif isNaN(value) then
        return condition.nan == true
    elseif condition.values[value] ~= nil then
        return true
    elseif typeof(value) == "buffer" then
        for expected in pairs(condition.values) do
            if typeof(expected) == "buffer" and buffersEqual(expected, value) then
                return true
            end
        end
    end

    return false
end

function Remote.new(instance, maxLogs, maxHistoryBytes)
    local remote = {}

    remote.Instance = instance
    remote.MaxLogs = normalizeMaxLogs(maxLogs)
    remote.MaxHistoryBytes = normalizeMaxHistoryBytes(maxHistoryBytes)
    remote.Logs = createLogBuffer(remote.MaxLogs, remote.MaxHistoryBytes)
    remote.HistoryBytes = 0
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
    remote.RefreshCallBytes = Remote.refreshCallBytes
    remote.DecrementCalls = Remote.decrementCalls

    return remote
end

function Remote.clear(remote)
    remote.Calls = 0
    remote.TotalCalls = 0
    remote.DroppedCalls = 0
    remote.Logs:Clear()
    remote.HistoryBytes = 0
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
    return addArgCondition(remote.BlockedArgs, index, value, byType)
end

function Remote.ignoreArg(remote, index, value, byType)
    return addArgCondition(remote.IgnoredArgs, index, value, byType)
end

function Remote.areArgsBlocked(remote, args)
    local blockedArgs = remote.BlockedArgs

    for index = 1, argumentCount(args) do
        local value = args[index]
        local indexBlock = blockedArgs[index]

        if indexBlock
            and (indexBlock.types[typeof(value)] or matchesValues(indexBlock, value))
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
            and (indexIgnore.types[typeof(value)] or matchesValues(indexIgnore, value))
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
    local droppedCount = logs:Push(call)

    if droppedCount > 0 then
        remote.DroppedCalls = remote.DroppedCalls + droppedCount
        dropped = droppedCount
    end

    remote.HistoryBytes = logs:Bytes()

    return dropped
end

function Remote.refreshCallBytes(remote, call)
    local dropped = remote.Logs:RefreshBytes(call)

    if dropped > 0 then
        remote.DroppedCalls = remote.DroppedCalls + dropped
    end

    remote.HistoryBytes = remote.Logs:Bytes()
    return dropped
end

function Remote.decrementCalls(remote, call)
    local logs = remote.Logs
    if logs:Remove(call) then
        remote.Calls = math.max(0, remote.Calls - 1)
        remote.HistoryBytes = logs:Bytes()
    end
end

return Remote
