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
        local bytes = tonumber(type(value) == "table" and rawget(value, "capturedBytes"))
        if not bytes or bytes ~= bytes or bytes == math.huge or bytes == -math.huge then
            return 0
        end
        return math.max(0, math.floor(bytes))
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

        -- A single oversized entry must not defeat the entire history budget.
        if bytes > byteCapacity then
            return 1
        end

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
        -- Synchronous calls complete at the newest slot. Avoid walking the
        -- complete history on every call; yielding calls retain the lookup path.
        local newest = count > 0 and physicalIndex(count)
        if newest and storage[newest] == target then
            found = newest
        else
            for logicalIndex = 1, count do
                if storage[physicalIndex(logicalIndex)] == target then
                    found = physicalIndex(logicalIndex)
                    break
                end
            end
        end

        if not found then
            return 0
        end

        local nextBytes = valueBytes(target)
        storedBytes = math.max(0, storedBytes - (sizes[found] or 0)) + nextBytes
        sizes[found] = nextBytes

        local dropped = 0

        while count > 0 and storedBytes > byteCapacity do
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


return createLogBuffer
