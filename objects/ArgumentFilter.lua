local function argumentCount(args)
    if type(args) ~= "table" then
        return 0
    end

    local count = rawget(args, "n")
    if type(count) == "number" and count == count and count ~= math.huge and count ~= -math.huge then
        return math.max(0, math.floor(count))
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
    if rawequal(left, right) then
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
    if maximum ~= maximum or maximum == math.huge or maximum == -math.huge then
        maximum = 4096
    end
    maximum = math.max(0, math.min(65536, math.floor(maximum)))

    local ran, matches = pcall(function()
        local leftLength = buffer.len(left)
        local rightLength = buffer.len(right)

        if type(leftLength) ~= "number" or leftLength ~= leftLength or leftLength < 0
            or leftLength % 1 ~= 0 or leftLength ~= rightLength or leftLength > maximum
        then
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
    end

    if byType or value == nil then
        local valueType = "nil"
        if byType then
            valueType = value
        end

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

    storage[index] = condition
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


local function matchesArgCondition(storage, args)
    local count = argumentCount(args)
    for index, condition in next, storage do
        local value = type(args) == "table" and rawget(args, index)

        if index <= count
            and (condition.types[typeof(value)] or matchesValues(condition, value))
        then
            return true
        end
    end

    return false
end


return { Add = addArgCondition, Matches = matchesArgCondition, Count = argumentCount }
