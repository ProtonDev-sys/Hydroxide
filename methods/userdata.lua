local methods = {}

local players = game:GetService("Players")
local client = players and players.LocalPlayer

local function quoteString(value)
    local parts = { '"' }

    for index = 1, #value do
        local byte = value:byte(index)

        if byte == 34 then
            parts[#parts + 1] = '\\"'
        elseif byte == 92 then
            parts[#parts + 1] = "\\\\"
        elseif byte == 7 then
            parts[#parts + 1] = "\\a"
        elseif byte == 8 then
            parts[#parts + 1] = "\\b"
        elseif byte == 9 then
            parts[#parts + 1] = "\\t"
        elseif byte == 10 then
            parts[#parts + 1] = "\\n"
        elseif byte == 11 then
            parts[#parts + 1] = "\\v"
        elseif byte == 12 then
            parts[#parts + 1] = "\\f"
        elseif byte == 13 then
            parts[#parts + 1] = "\\r"
        elseif byte < 32 or byte > 126 then
            parts[#parts + 1] = ("\\%03d"):format(byte)
        else
            parts[#parts + 1] = string.char(byte)
        end
    end

    parts[#parts + 1] = '"'
    return table.concat(parts)
end

local function joinValues(values)
    local parts = {}

    for index, value in ipairs(values) do
        parts[index] = tostring(value)
    end

    return table.concat(parts, ", ")
end

local function getInstancePath(instance)
    if instance == game then
        return "game"
    elseif typeof(instance) ~= "Instance" then
        return "nil --[[ Value is not an Instance ]]"
    end

    local ancestry = {}
    local seen = {}
    local current = instance

    while current ~= game do
        if seen[current] or #ancestry >= 128 then
            return "nil --[[ Invalid or cyclic Instance path ]]"
        end

        seen[current] = true
        ancestry[#ancestry + 1] = current

        local parentRan, parent = pcall(function()
            return current.Parent
        end)

        if not parentRan or parent == nil then
            local nameRan, name = pcall(function()
                return current.Name
            end)
            local description = nameRan and tostring(name):gsub("[%c]", " ") or "unknown"
            return "nil --[[ Detached or destroyed Instance: " .. description:gsub("%]%]", "] ]") .. " ]]"
        end

        current = parent
    end

    local path = "game"

    for index = #ancestry, 1, -1 do
        local object = ancestry[index]
        local nameRan, name = pcall(function()
            return object.Name
        end)
        local classRan, className = pcall(function()
            return object.ClassName
        end)
        local serviceRan, service = false, nil

        if index == #ancestry and classRan and type(className) == "string" then
            serviceRan, service = pcall(game.GetService, game, className)
        end

        if serviceRan and service == object then
            path = path .. ":GetService(" .. quoteString(className) .. ")"
        elseif object == client then
            path = path .. ".LocalPlayer"
        elseif nameRan and type(name) == "string" then
            path = path .. "[" .. quoteString(name) .. "]"
        else
            return "nil --[[ Unreadable Instance path ]]"
        end
    end

    return path
end

local function bufferValue(data)
    if not buffer or type(buffer.len) ~= "function" or type(buffer.tostring) ~= "function" then
        return "nil --[[ buffer serialization unavailable ]]"
    end

    local measured, byteLength = pcall(buffer.len, data)
    local settings = oh and oh.Settings or {}
    local maximum = tonumber(settings.MaxGeneratedBufferBytes or settings.maxGeneratedBufferBytes) or 65536

    if not measured or type(byteLength) ~= "number" then
        return "nil --[[ unreadable buffer ]]"
    elseif byteLength > maximum then
        return "nil --[[ buffer exceeds configured byte limit ]]"
    end

    local ok, serialized = pcall(buffer.tostring, data)

    if not ok or type(serialized) ~= "string" or #serialized ~= byteLength or #serialized > maximum then
        return "nil --[[ unreadable buffer ]]"
    end

    return "buffer.fromstring(" .. quoteString(serialized) .. ")"
end

local function sequenceValue(sequenceType, keypoints)
    local values = {}

    for index, keypoint in ipairs(keypoints) do
        values[index] = userdataValue(keypoint)
    end

    return sequenceType .. ".new({" .. table.concat(values, ", ") .. "})"
end

local function userdataValue(data)
    local dataType = typeof(data)

    if dataType == "buffer" then
        return bufferValue(data)
    elseif dataType == "userdata" then
        return "nil --[[ unsupported userdata ]]"
    elseif dataType == "Instance" then
        return getInstancePath(data)
    elseif dataType == "BrickColor" then
        return dataType .. '.new("' .. tostring(data) .. '")'
    elseif dataType == "NumberRange" then
        return ("NumberRange.new(%s, %s)"):format(tostring(data.Min), tostring(data.Max))
    elseif dataType == "DateTime" then
        return ("DateTime.fromUnixTimestampMillis(%s)"):format(tostring(data.UnixTimestampMillis))
    elseif dataType == "EnumItem" then
        return tostring(data.EnumType) .. "." .. data.Name
    elseif dataType == "Ray" then
        return ("Ray.new(%s, %s)"):format(dataToString(data.Origin), dataToString(data.Direction))
    elseif dataType == "Region3" then
        return ("Region3.new(%s, %s)"):format(dataToString(data.CFrame.Position - data.Size / 2), dataToString(data.CFrame.Position + data.Size / 2))
    elseif dataType == "ColorSequence" then
        return sequenceValue("ColorSequence", data.Keypoints)
    elseif dataType == "NumberSequence" then
        return sequenceValue("NumberSequence", data.Keypoints)
    elseif dataType == "ColorSequenceKeypoint" then
        return ("ColorSequenceKeypoint.new(%s, %s)"):format(tostring(data.Time), dataToString(data.Value))
    elseif dataType == "NumberSequenceKeypoint" then
        return ("NumberSequenceKeypoint.new(%s, %s, %s)"):format(
            tostring(data.Time),
            tostring(data.Value),
            tostring(data.Envelope)
        )
    elseif dataType == "PathWaypoint" then
        return ("PathWaypoint.new(%s, %s, %s)"):format(
            dataToString(data.Position),
            tostring(data.Action),
            quoteString(data.Label or "")
        )
    elseif dataType == "PhysicalProperties" then
        return ("PhysicalProperties.new(%s)"):format(joinValues({
            data.Density,
            data.Friction,
            data.Elasticity,
            data.FrictionWeight,
            data.ElasticityWeight
        }))
    elseif dataType == "TweenInfo" then
        return ("TweenInfo.new(%s)"):format(joinValues({
            data.Time,
            data.EasingStyle,
            data.EasingDirection,
            data.RepeatCount,
            data.Reverses,
            data.DelayTime
        }))
    elseif dataType == "CFrame" then
        return ("CFrame.new(%s)"):format(joinValues({ data:GetComponents() }))
    elseif dataType == "Color3" then
        return ("Color3.new(%s, %s, %s)"):format(tostring(data.R), tostring(data.G), tostring(data.B))
    elseif dataType == "Vector3" then
        return ("Vector3.new(%s, %s, %s)"):format(tostring(data.X), tostring(data.Y), tostring(data.Z))
    elseif dataType == "Vector2" then
        return ("Vector2.new(%s, %s)"):format(tostring(data.X), tostring(data.Y))
    elseif dataType == "UDim2" then
        return ("UDim2.new(%s, %s, %s, %s)"):format(
            tostring(data.X.Scale),
            tostring(data.X.Offset),
            tostring(data.Y.Scale),
            tostring(data.Y.Offset)
        )
    elseif dataType == "UDim" then
        return ("UDim.new(%s, %s)"):format(tostring(data.Scale), tostring(data.Offset))
    elseif dataType == "Rect" then
        return ("Rect.new(%s, %s, %s, %s)"):format(
            tostring(data.Min.X),
            tostring(data.Min.Y),
            tostring(data.Max.X),
            tostring(data.Max.Y)
        )
    elseif dataType == "Axes" or dataType == "Faces" or dataType == "Random" or dataType == "RaycastParams" then
        return "nil --[[ unsupported " .. dataType .. " value ]]"
    end

    return tostring(data)
end

local function isUserdata(valueType)
    return valueType == "BrickColor"
        or valueType == "TweenInfo"
        or valueType == "Instance"
        or valueType == "DateTime"
        or valueType == "Vector3"
        or valueType == "Vector2"
        or valueType == "Region3"
        or valueType == "CFrame"
        or valueType == "Color3"
        or valueType == "Random"
        or valueType == "Faces"
        or valueType == "UDim2"
        or valueType == "UDim"
        or valueType == "Rect"
        or valueType == "Axes"
        or valueType == "Ray"
        or valueType == "RaycastParams"
        or valueType == "PathWaypoint"
        or valueType == "PhysicalProperties"
        or valueType == "ColorSequence"
        or valueType == "ColorSequenceKeypoint"
        or valueType == "NumberRange"
        or valueType == "NumberSequence"
        or valueType == "NumberSequenceKeypoint"
        or valueType == "EnumItem"
        or valueType == "buffer"
end

methods.isUserdata = isUserdata
methods.userdataValue = userdataValue
methods.getInstancePath = getInstancePath
return methods
