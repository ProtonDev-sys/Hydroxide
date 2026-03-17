local methods = {}

local players = game:GetService("Players")
local client = players and players.LocalPlayer

local function quoteString(value)
    return dataToString(value)
end

local function joinValues(values)
    local parts = {}

    for index, value in ipairs(values) do
        parts[index] = tostring(value)
    end

    return table.concat(parts, ", ")
end

local function getInstancePath(instance)
    local name = instance.Name
    local head = (#name > 0 and "." .. name) or "['']"

    if not instance.Parent and instance ~= game then
        return head .. " --[[ PARENTED TO NIL OR DESTROYED ]]"
    end

    if instance == game then
        return "game"
    elseif instance == workspace then
        return "workspace"
    else
        local _, service = pcall(game.GetService, game, instance.ClassName)

        if service == instance then
            head = ':GetService("' .. instance.ClassName .. '")'
        elseif instance == client then
            head = ".LocalPlayer"
        else
            local nonAlphaNum = name:gsub("[%w_]", "")
            local noPunctuation = nonAlphaNum:gsub("[%s%p]", "")

            if tonumber(name:sub(1, 1)) or (#nonAlphaNum ~= 0 and #noPunctuation == 0) then
                head = '["' .. name:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"]'
            elseif #nonAlphaNum ~= 0 and #noPunctuation > 0 then
                head = "[" .. toUnicode(name) .. "]"
            end
        end
    end

    return getInstancePath(instance.Parent) .. head
end

local function bufferValue(data)
    if not buffer or not buffer.tostring then
        return "buffer.fromstring(\"\")"
    end

    local ok, serialized = pcall(buffer.tostring, data)

    if not ok then
        return "buffer.fromstring(\"\")"
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
        return "aux.placeholderUserdataConstant"
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
            tostring(data.Label or '""')
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
        return dataType .. ".new(" .. tostring(data) .. ")"
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
