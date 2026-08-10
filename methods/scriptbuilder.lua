local methods = {}

local ALLOWED_METHODS = {
	FireServer = true,
	InvokeServer = true,
	Fire = true,
	Invoke = true,
}

local DEFAULTS = {
	MaxGeneratedTableEntries = 256,
	MaxGeneratedTables = 512,
	MaxGeneratedTableDepth = 16,
	MaxGeneratedStringBytes = 65536,
	MaxGeneratedBufferBytes = 65536,
	MaxGeneratedOutputBytes = 1048576,
}

local function safeTypeof(value)
	if type(typeof) == "function" then
		local ran, valueType = pcall(typeof, value)

		if ran and type(valueType) == "string" then
			return valueType
		end
	end

	return type(value)
end

local function safeTostring(value)
	local ran, result = pcall(tostring, value)
	return ran and result or "<unprintable>"
end

local function lowerSettingName(name)
	return name:sub(1, 1):lower() .. name:sub(2)
end

local function settingNumber(name, minimum, maximum)
	local settings = oh and oh.Settings or {}
	local value = tonumber(settings[name] or settings[lowerSettingName(name)]) or DEFAULTS[name]

	value = math.floor(value)
	return math.max(minimum, math.min(maximum, value))
end

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

local function commentText(value, maxLength)
	value = safeTostring(value):gsub("[%c]", " "):gsub("%s+", " ")
	maxLength = maxLength or 360

	if #value > maxLength then
		value = value:sub(1, maxLength - 3) .. "..."
	end

	return value
end

local function getArgCount(args)
	if type(args) ~= "table" then
		return 0
	end

	local count = tonumber(args.n) or #args
	return math.max(0, math.floor(count))
end

local function getInstanceExpression(instance)
	if safeTypeof(instance) ~= "Instance" then
		return nil, "the captured remote is not an Instance"
	elseif instance == game then
		return "game"
	end

	local localPlayer
	local playersRan, players = pcall(game.GetService, game, "Players")

	if playersRan and players then
		pcall(function()
			localPlayer = players.LocalPlayer
		end)
	end

	local ancestry = {}
	local seen = {}
	local current = instance

	while current ~= game do
		if seen[current] then
			return nil, "the captured Instance ancestry contains a cycle"
		elseif #ancestry >= 128 then
			return nil, "the captured Instance ancestry is too deep"
		end

		seen[current] = true
		ancestry[#ancestry + 1] = current

		local parentRan, parent = pcall(function()
			return current.Parent
		end)

		if not parentRan or parent == nil then
			return nil, "the captured Instance is detached or destroyed"
		end

		current = parent
	end

	local expression = "game"

	for index = #ancestry, 1, -1 do
		local object = ancestry[index]
		local nameRan, name = pcall(function()
			return object.Name
		end)
		local classRan, className = pcall(function()
			return object.ClassName
		end)
		local isService = false

		if index == #ancestry and classRan and type(className) == "string" and type(game.GetService) == "function" then
			local serviceRan, service = pcall(game.GetService, game, className)
			isService = serviceRan and service == object
		end

		if isService then
			expression = expression .. ":GetService(" .. quoteString(className) .. ")"
		elseif object == localPlayer then
			expression = expression .. ".LocalPlayer"
		elseif nameRan and type(name) == "string" then
			expression = expression .. "[" .. quoteString(name) .. "]"
		else
			return nil, "an Instance in the captured path has no readable name"
		end
	end

	return expression
end

local function makeState()
	local maxOutputBytes = settingNumber("MaxGeneratedOutputBytes", 16384, 8388608)

	return {
		ids = {},
		order = {},
		entries = {},
		total = 0,
		warnings = {},
		warningKeys = {},
		maxEntries = settingNumber("MaxGeneratedTableEntries", 8, 5000),
		maxTables = settingNumber("MaxGeneratedTables", 8, 5000),
		maxDepth = settingNumber("MaxGeneratedTableDepth", 1, 64),
		maxStringBytes = settingNumber("MaxGeneratedStringBytes", 256, 1048576),
		maxBufferBytes = settingNumber("MaxGeneratedBufferBytes", 256, 1048576),
		maxOutputBytes = maxOutputBytes,
		maxCollectedEntries = math.max(8, math.floor(maxOutputBytes / 48)),
		collectedEntries = 0,
		outputBytes = 0,
	}
end

local function addWarning(state, key, message)
	key = key or message

	if state.warningKeys[key] or #state.warnings >= 100 then
		return
	end

	state.warningKeys[key] = true
	state.warnings[#state.warnings + 1] = commentText(message)
end

local function readEntries(value, state)
	local cached = state.entries[value]

	if cached then
		return cached
	end

	local entries = {}
	local previous

	while true do
		local ran, key, child = pcall(next, value, previous)

		if not ran then
			addWarning(state, "table-iteration", "A table could not be iterated safely and was emitted partially.")
			break
		elseif key == nil then
			break
		elseif #entries >= state.maxEntries then
			addWarning(
				state,
				"table-entry-limit:" .. safeTostring(value),
				("A table was truncated after %d entries to keep generation responsive."):format(state.maxEntries)
			)
			break
		elseif state.collectedEntries >= state.maxCollectedEntries then
			addWarning(
				state,
				"table-graph-output-budget",
				"The captured table graph was truncated before it could exceed the generated-output budget."
			)
			break
		end

		entries[#entries + 1] = { key, child }
		state.collectedEntries = state.collectedEntries + 1
		previous = key
	end

	state.entries[value] = entries
	return entries
end

local function collectTables(value, state, depth)
	if type(value) ~= "table" or safeTypeof(value) ~= "table" then
		return
	elseif state.ids[value] then
		return
	elseif depth > state.maxDepth then
		addWarning(state, "table-depth", "A nested table exceeded the configured depth limit and was omitted.")
		return
	elseif state.total >= state.maxTables then
		addWarning(state, "table-count", "The captured table graph exceeded the configured table limit and was truncated.")
		return
	end

	state.total = state.total + 1
	state.ids[value] = state.total
	state.order[state.total] = value

	for _, entry in ipairs(readEntries(value, state)) do
		collectTables(entry[1], state, depth + 1)
		collectTables(entry[2], state, depth + 1)
	end
end

local function makeSerializer(state)
	local serialize

	local function unsupported(valueType, isKey, reason)
		addWarning(
			state,
			"unsupported:" .. tostring(valueType) .. ":" .. tostring(reason),
			("A %s value was %s because it cannot be reconstructed safely%s."):format(
				tostring(valueType),
				isKey and "omitted as a table key" or "replaced with nil",
				reason and (" (" .. reason .. ")") or ""
			)
		)

		return isKey and nil or "nil", not isKey
	end

	local function serializeNumber(value)
		if value ~= value then
			return "(0 / 0)"
		elseif value == math.huge then
			return "math.huge"
		elseif value == -math.huge then
			return "-math.huge"
		end

		return tostring(value)
	end

	local function serializeArray(values)
		local expressions = {}

		for index, value in ipairs(values) do
			local expression = serialize(value, false)
			expressions[index] = expression or "nil"
		end

		return table.concat(expressions, ", ")
	end

	local function serializeRoblox(value, valueType, isKey)
		if valueType == "Instance" then
			local expression, pathError = getInstanceExpression(value)

			if expression then
				return expression, true
			end

			return unsupported(valueType, isKey, pathError)
		elseif valueType == "buffer" then
			if not buffer or type(buffer.tostring) ~= "function" then
				return unsupported(valueType, isKey, "buffer.tostring is unavailable")
			end

			local ran, bytes = pcall(buffer.tostring, value)

			if not ran or type(bytes) ~= "string" then
				return unsupported(valueType, isKey, "buffer contents could not be read")
			elseif #bytes > state.maxBufferBytes then
				return unsupported(valueType, isKey, "buffer exceeds the configured byte limit")
			end

			return "buffer.fromstring(" .. quoteString(bytes) .. ")", true
		end

		local ran, expression = pcall(function()
			if valueType == "BrickColor" then
				return "BrickColor.new(" .. quoteString(tostring(value)) .. ")"
			elseif valueType == "NumberRange" then
				return ("NumberRange.new(%s, %s)"):format(serializeNumber(value.Min), serializeNumber(value.Max))
			elseif valueType == "DateTime" then
				return ("DateTime.fromUnixTimestampMillis(%s)"):format(serializeNumber(value.UnixTimestampMillis))
			elseif valueType == "EnumItem" then
				local enumTypeName = tostring(value.EnumType):match("^Enum%.(.+)$")

				if not enumTypeName then
					error("Enum type name is unavailable")
				end

				return ("Enum[%s][%s]"):format(quoteString(enumTypeName), quoteString(value.Name))
			elseif valueType == "Vector3" then
				return ("Vector3.new(%s, %s, %s)"):format(
					serializeNumber(value.X),
					serializeNumber(value.Y),
					serializeNumber(value.Z)
				)
			elseif valueType == "Vector2" then
				return ("Vector2.new(%s, %s)"):format(serializeNumber(value.X), serializeNumber(value.Y))
			elseif valueType == "Color3" then
				return ("Color3.new(%s, %s, %s)"):format(
					serializeNumber(value.R),
					serializeNumber(value.G),
					serializeNumber(value.B)
				)
			elseif valueType == "UDim" then
				return ("UDim.new(%s, %s)"):format(serializeNumber(value.Scale), serializeNumber(value.Offset))
			elseif valueType == "UDim2" then
				return ("UDim2.new(%s, %s, %s, %s)"):format(
					serializeNumber(value.X.Scale),
					serializeNumber(value.X.Offset),
					serializeNumber(value.Y.Scale),
					serializeNumber(value.Y.Offset)
				)
			elseif valueType == "Rect" then
				return ("Rect.new(%s, %s, %s, %s)"):format(
					serializeNumber(value.Min.X),
					serializeNumber(value.Min.Y),
					serializeNumber(value.Max.X),
					serializeNumber(value.Max.Y)
				)
			elseif valueType == "CFrame" then
				return "CFrame.new(" .. serializeArray({ value:GetComponents() }) .. ")"
			elseif valueType == "Ray" then
				return ("Ray.new(%s, %s)"):format(serialize(value.Origin, false), serialize(value.Direction, false))
			elseif valueType == "Region3" then
				local minimum = value.CFrame.Position - value.Size / 2
				local maximum = value.CFrame.Position + value.Size / 2
				return ("Region3.new(%s, %s)"):format(serialize(minimum, false), serialize(maximum, false))
			elseif valueType == "ColorSequenceKeypoint" then
				return ("ColorSequenceKeypoint.new(%s, %s)"):format(
					serializeNumber(value.Time),
					serialize(value.Value, false)
				)
			elseif valueType == "NumberSequenceKeypoint" then
				return ("NumberSequenceKeypoint.new(%s, %s, %s)"):format(
					serializeNumber(value.Time),
					serializeNumber(value.Value),
					serializeNumber(value.Envelope)
				)
			elseif valueType == "ColorSequence" or valueType == "NumberSequence" then
				return valueType .. ".new({" .. serializeArray(value.Keypoints) .. "})"
			elseif valueType == "PathWaypoint" then
				return ("PathWaypoint.new(%s, %s, %s)"):format(
					serialize(value.Position, false),
					serialize(value.Action, false),
					quoteString(value.Label or "")
				)
			elseif valueType == "PhysicalProperties" then
				return ("PhysicalProperties.new(%s)"):format(serializeArray({
					value.Density,
					value.Friction,
					value.Elasticity,
					value.FrictionWeight,
					value.ElasticityWeight,
				}))
			elseif valueType == "TweenInfo" then
				return ("TweenInfo.new(%s)"):format(serializeArray({
					value.Time,
					value.EasingStyle,
					value.EasingDirection,
					value.RepeatCount,
					value.Reverses,
					value.DelayTime,
				}))
			end
		end)

		if ran and type(expression) == "string" and expression ~= "" then
			return expression, true
		end

		return unsupported(valueType, isKey, ran and "unsupported Roblox datatype" or expression)
	end

	serialize = function(value, isKey)
		local rawType = type(value)
		local valueType = safeTypeof(value)

		if valueType == "Instance" or valueType == "buffer" or (rawType == "userdata" and valueType ~= "userdata") then
			return serializeRoblox(value, valueType, isKey)
		elseif rawType == "table" and valueType ~= "table" then
			return serializeRoblox(value, valueType, isKey)
		elseif rawType == "table" then
			local id = state.ids[value]

			if id then
				return ("OH_Table_%d"):format(id), true
			end

			return unsupported("table", isKey, "table graph limit reached")
		elseif rawType == "string" then
			if #value > state.maxStringBytes then
				return unsupported("string", isKey, "string exceeds the configured byte limit")
			end

			return quoteString(value), true
		elseif rawType == "number" then
			return serializeNumber(value), true
		elseif rawType == "boolean" then
			return tostring(value), true
		elseif rawType == "nil" then
			return "nil", not isKey
		elseif rawType == "function" or rawType == "thread" or rawType == "userdata" then
			return unsupported(valueType, isKey)
		end

		return unsupported(valueType, isKey)
	end

	return serialize
end

local function appendLine(lines, state, line)
	line = tostring(line or "")

	if state.outputBytes + #line + 1 > state.maxOutputBytes then
		return false
	end

	state.outputBytes = state.outputBytes + #line + 1
	lines[#lines + 1] = line
	return true
end

local function emitTables(lines, state, serialize)
	if #state.order == 0 then
		return true
	end

	if not appendLine(lines, state, "-- Table locals preserve cyclic and shared references.") then
		return false
	end

	for id = 1, #state.order do
		if not appendLine(lines, state, ("local OH_Table_%d = {}"):format(id)) then
			return false
		end
	end

	if not appendLine(lines, state, "") then
		return false
	end

	for id, tableValue in ipairs(state.order) do
		for _, entry in ipairs(readEntries(tableValue, state)) do
			local keyExpression, keySupported = serialize(entry[1], true)
			local valueExpression = serialize(entry[2], false)

			if keySupported and keyExpression then
				if not appendLine(
					lines,
					state,
					("OH_Table_%d[%s] = %s"):format(id, keyExpression, valueExpression or "nil")
				) then
					return false
				end
			end
		end
	end

	return appendLine(lines, state, "")
end

local function buildRemoteScript(remoteInstance, method, args, callInfo)
	if not ALLOWED_METHODS[method] then
		return nil, "Unsupported remote method: " .. commentText(method or "nil", 80)
	end

	local remotePath, pathError = getInstanceExpression(remoteInstance)

	if not remotePath then
		return nil, "Cannot generate a replay script: " .. tostring(pathError)
	end

	args = type(args) == "table" and args or {}
	local argCount = getArgCount(args)
	local state = makeState()

	for index = 1, argCount do
		collectTables(args[index], state, 0)
	end

	local serialize = makeSerializer(state)
	local body = {}
	local prelude = {
		"local OH_Unpack = table.unpack or unpack",
		"local OH_Remote = " .. remotePath,
		("local OH_Args = table.create and table.create(%d) or {}"):format(argCount),
		("OH_Args.n = %d"):format(argCount),
		"",
	}

	for _, line in ipairs(prelude) do
		if not appendLine(body, state, line) then
			return nil, ("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
		end
	end

	if not emitTables(body, state, serialize) then
		return nil, ("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
	end

	for index = 1, argCount do
		local expression = serialize(args[index], false)

		if not appendLine(body, state, ("OH_Args[%d] = %s"):format(index, expression or "nil")) then
			return nil, ("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
		end
	end

	if not appendLine(body, state, "")
		or not appendLine(body, state, ("return OH_Remote:%s(OH_Unpack(OH_Args, 1, OH_Args.n))"):format(method))
	then
		return nil, ("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
	end

	local header = {
		"-- Generated by Hydroxide RemoteSpy",
		"-- Fork: https://github.com/ProtonDev-sys/Hydroxide/tree/potassium-modernization-fork",
		"-- Review before running: replaying a call can change game state.",
		("-- Method: %s | Arguments: %d"):format(method, argCount),
	}

	if type(callInfo) == "table" then
		if callInfo.timestamp ~= nil then
			header[#header + 1] = "-- Captured at: " .. commentText(callInfo.timestamp)
		end

		if safeTypeof(callInfo.script) == "Instance" then
			local callingPath = getInstanceExpression(callInfo.script)

			if callingPath then
				header[#header + 1] = "-- Calling script: " .. callingPath
			end
		end
	end

	for _, warning in ipairs(state.warnings) do
		header[#header + 1] = "-- Warning: " .. warning
	end

	header[#header + 1] = ""
	local generated = table.concat(header, "\n") .. table.concat(body, "\n")

	if #generated > state.maxOutputBytes then
		return nil, ("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
	end

	return generated
end


methods.buildRemoteScript = buildRemoteScript
methods.getReplayInstancePath = getInstanceExpression
return methods
