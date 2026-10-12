local methods = {}

local ALLOWED_METHODS = {
	FireServer = true,
	InvokeServer = true,
	Fire = true,
	Invoke = true,
}

local LUA_KEYWORDS = {
	["and"] = true,
	["break"] = true,
	["continue"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["export"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["type"] = true,
	["until"] = true,
	["while"] = true,
}

local MAX_INLINE_TABLE_BYTES = 96
local MAX_INLINE_CALL_BYTES = 140

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
	if value ~= value or value == math.huge or value == -math.huge then
		value = DEFAULTS[name]
	end

	value = math.floor(value)
	return math.max(minimum, math.min(maximum, value))
end

local escapes = {
    ['"'] = '\\"', ['\\'] = '\\\\',
    ['\a'] = '\\a', ['\b'] = '\\b', ['\t'] = '\\t', ['\n'] = '\\n',
    ['\v'] = '\\v', ['\f'] = '\\f', ['\r'] = '\\r'
}

local function escapeString(value)
    return (value:gsub('[%z\1-\31\127-\255"\\]', function(character)
        return escapes[character] or ("\\%03d"):format(character:byte())
    end))
end

local function quoteString(value)
    return '"' .. escapeString(value) .. '"'
end

local function commentText(value, maxLength)
	value = safeTostring(value):gsub("[%c]", " "):gsub("%s+", " ")
	maxLength = maxLength or 360

	if #value > maxLength then
		value = value:sub(1, maxLength - 3) .. "..."
	end

	return value
end

local function validateGeneratedSource(source, chunkName)
	if type(source) ~= "string" or source == "" then
		return false, "generated source is empty"
	elseif type(loadstring) ~= "function" then
		-- Unit-test and compatibility runtimes may expose load rather than
		-- loadstring. Callers still receive bounded source and can validate it
		-- with their own compiler; Potassium provides loadstring.
		return true
	end

	local ran, chunk, compileError = pcall(loadstring, source, chunkName or "@HydroxideGeneratedReplay")

	if not ran then
		return false, commentText(chunk, 360)
	elseif type(chunk) ~= "function" then
		return false, commentText(compileError or "the compiler returned no function", 360)
	end

	return true
end

local function getArgCount(args)
	if type(args) ~= "table" then
		return 0
	end

	local count = tonumber(rawget(args, "n")) or #args
	if count ~= count or count == math.huge or count == -math.huge or count < 0 or count > 1024 then
		return nil
	end
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
		references = {},
		graphTables = {},
		rendering = {},
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
	end

	state.references[value] = (state.references[value] or 0) + 1

	if state.ids[value] then
		return
	elseif depth > state.maxDepth then
		addWarning(state, "table-depth", "A nested table exceeded the configured depth limit and was omitted.")
		return
	elseif state.total >= state.maxTables then
		addWarning(
			state,
			"table-count",
			"The captured table graph exceeded the configured table limit and was truncated."
		)
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

local function markGraphTables(state)
	local links = {}

	for _, tableValue in ipairs(state.order) do
		links[tableValue] = {}
	end

	for _, tableValue in ipairs(state.order) do
		for _, entry in ipairs(readEntries(tableValue, state)) do
			for index = 1, 2 do
				local child = entry[index]

				if type(child) == "table" and safeTypeof(child) == "table" and state.ids[child] then
					links[tableValue][child] = true
					links[child][tableValue] = true
				end
			end
		end
	end

	local visited = {}

	for _, tableValue in ipairs(state.order) do
		if not visited[tableValue] then
			local component = {}
			local stack = { tableValue }
			local requiresGraph = false
			visited[tableValue] = true

			while #stack > 0 do
				local current = stack[#stack]
				stack[#stack] = nil
				component[#component + 1] = current

				if (state.references[current] or 0) > 1 then
					requiresGraph = true
				end

				for linked in pairs(links[current]) do
					if not visited[linked] then
						visited[linked] = true
						stack[#stack + 1] = linked
					end
				end
			end

			if requiresGraph then
				for _, member in ipairs(component) do
					state.graphTables[member] = true
				end
			end
		end
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
			if not buffer or type(buffer.len) ~= "function" or type(buffer.tostring) ~= "function" then
				return unsupported(valueType, isKey, "buffer.len or buffer.tostring is unavailable")
			end

			local measured, byteLength = pcall(buffer.len, value)

			if not measured or type(byteLength) ~= "number" or byteLength ~= byteLength
				or byteLength < 0 or byteLength == math.huge or byteLength % 1 ~= 0
			then
				return unsupported(valueType, isKey, "buffer length could not be read")
			elseif byteLength > state.maxBufferBytes then
				return unsupported(valueType, isKey, "buffer exceeds the configured byte limit")
			elseif byteLength > state.maxOutputBytes then
				state.outputExceeded = true
				return "nil", not isKey
			end

			local ran, bytes = pcall(buffer.tostring, value)

			if not ran or type(bytes) ~= "string" then
				return unsupported(valueType, isKey, "buffer contents could not be read")
			elseif #bytes ~= byteLength then
				return unsupported(valueType, isKey, "buffer contents length did not match buffer.len")
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

	local function isIdentifier(value)
		return type(value) == "string" and value:match("^[%a_][%w_]*$") ~= nil and not LUA_KEYWORDS[value]
	end

	local function serializeTable(value, isKey, indentLevel)
		local id = state.ids[value]

		if not id then
			return unsupported("table", isKey, "table graph limit reached")
		elseif state.graphTables[value] then
			return ("OH_Tables[%d]"):format(id), true
		elseif state.rendering[value] then
			return unsupported("table", isKey, "cyclic table analysis failed")
		end

		state.rendering[value] = true

		local entries = readEntries(value, state)
		local arrayValues = {}
		local maximumIndex = 0
		local isArray = true

		for _, entry in ipairs(entries) do
			local key = entry[1]

			if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
				isArray = false
				break
			end

			maximumIndex = math.max(maximumIndex, key)
			arrayValues[key] = entry[2]
		end

		if maximumIndex ~= #entries then
			isArray = false
		end

		local fields = {}
		local fieldBytes = 0
		local function addField(field)
			if state.outputExceeded then
				return false
			end
			fieldBytes = fieldBytes + #field + indentLevel + 4
			if fieldBytes > state.maxOutputBytes then
				state.outputExceeded = true
				return false
			end
			fields[#fields + 1] = field
			return true
		end

		if isArray then
			for index = 1, maximumIndex do
				local expression = serialize(arrayValues[index], false, indentLevel + 1)
				if not addField(expression or "nil") then
					break
				end
			end
		else
			for _, entry in ipairs(entries) do
				local key = entry[1]
				local keyExpression, keySupported = serialize(key, true, indentLevel + 1)

				if keySupported and keyExpression then
					local valueExpression = serialize(entry[2], false, indentLevel + 1) or "nil"

					local field = isIdentifier(key) and (key .. " = " .. valueExpression)
						or ("[" .. keyExpression .. "] = " .. valueExpression)
					if not addField(field) then
						break
					end
				end
			end
		end

		state.rendering[value] = nil

		if #fields == 0 then
			return "{}", true
		end

		local compact = "{ " .. table.concat(fields, ", ") .. " }"

		if #compact <= MAX_INLINE_TABLE_BYTES and not compact:find("\n", 1, true) then
			return compact, true
		end

		local fieldIndent = string.rep("\t", indentLevel + 1)
		local closingIndent = string.rep("\t", indentLevel)

		return "{\n" .. fieldIndent .. table.concat(fields, ",\n" .. fieldIndent) .. ",\n" .. closingIndent .. "}", true
	end

	serialize = function(value, isKey, indentLevel)
		if state.outputExceeded then
			return "nil", not isKey
		end
		indentLevel = indentLevel or 0
		local rawType = type(value)
		local valueType = safeTypeof(value)

		if valueType == "Instance" or valueType == "buffer" or (rawType == "userdata" and valueType ~= "userdata") then
			return serializeRoblox(value, valueType, isKey)
		elseif rawType == "table" and valueType ~= "table" then
			return serializeRoblox(value, valueType, isKey)
		elseif rawType == "table" then
			return serializeTable(value, isKey, indentLevel)
		elseif rawType == "string" then
			if #value > state.maxStringBytes then
				return unsupported("string", isKey, "string exceeds the configured byte limit")
			elseif #value > state.maxOutputBytes then
				state.outputExceeded = true
				return "nil", not isKey
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

	if state.outputExceeded or state.outputBytes + #line + 1 > state.maxOutputBytes then
		return false
	end

	state.outputBytes = state.outputBytes + #line + 1
	lines[#lines + 1] = line
	return true
end

local function hasGraphTables(state)
	for _, tableValue in ipairs(state.order) do
		if state.graphTables[tableValue] then
			return true
		end
	end

	return false
end

local function emitTables(lines, state, serialize)
	if not hasGraphTables(state) then
		return true
	end
	if not appendLine(lines, state, "local OH_Tables = {}") then
		return false
	end

	for id, tableValue in ipairs(state.order) do
		if state.graphTables[tableValue] and not appendLine(lines, state, ("OH_Tables[%d] = {}"):format(id)) then
			return false
		end
	end

	if not appendLine(lines, state, "") then
		return false
	end

	for id, tableValue in ipairs(state.order) do
		if state.graphTables[tableValue] then
			for _, entry in ipairs(readEntries(tableValue, state)) do
				local keyExpression, keySupported = serialize(entry[1], true)

				if keySupported and keyExpression then
					local valueExpression = serialize(entry[2], false)

					if
						not appendLine(
							lines,
							state,
							("OH_Tables[%d][%s] = %s"):format(id, keyExpression, valueExpression or "nil")
						)
					then
						return false
					end
				end
			end
		end
	end

	return appendLine(lines, state, "")
end

local function emitRemoteCall(lines, state, remotePath, method, args, argCount, serialize)
	local expressions = {}
	local expressionBytes = #remotePath + #method + 12

	for index = 1, argCount do
		expressions[index] = serialize(rawget(args, index), false, 1) or "nil"
		expressionBytes = expressionBytes + #expressions[index] + 2
		if state.outputExceeded or expressionBytes > state.maxOutputBytes then
			return false
		end
	end

	local prefix = ("return %s:%s("):format(remotePath, method)
	local compactCall = prefix .. table.concat(expressions, ", ") .. ")"

	if argCount == 0 or (#compactCall <= MAX_INLINE_CALL_BYTES and not compactCall:find("\n", 1, true)) then
		return appendLine(lines, state, compactCall)
	elseif not appendLine(lines, state, prefix) then
		return false
	end

	for index, expression in ipairs(expressions) do
		local suffix = index < argCount and "," or ""

		if not appendLine(lines, state, "\t" .. expression .. suffix) then
			return false
		end
	end

	return appendLine(lines, state, ")")
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
	if not argCount then
		return nil, "Cannot generate a replay script: argument count must be between 0 and 1024"
	end
	local state = makeState()

	for index = 1, argCount do
		collectTables(rawget(args, index), state, 0)
	end

	markGraphTables(state)

	local serialize = makeSerializer(state)
	local body = {}

	if not emitTables(body, state, serialize) then
		return nil, ("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
	end

	if argCount > 128 then
		local prelude = {
			"local OH_Unpack = table.unpack or unpack",
			"local OH_Remote = " .. remotePath,
			("local OH_Args = table.create and table.create(%d) or {}"):format(argCount),
			("OH_Args.n = %d"):format(argCount),
			"",
		}

		for _, line in ipairs(prelude) do
			if not appendLine(body, state, line) then
				return nil,
					("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
			end
		end

		for index = 1, argCount do
			local expression = serialize(rawget(args, index), false)

			if not appendLine(body, state, ("OH_Args[%d] = %s"):format(index, expression or "nil")) then
				return nil,
					("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
			end
		end

		if
			not appendLine(body, state, "")
			or not appendLine(body, state, ("return OH_Remote:%s(OH_Unpack(OH_Args, 1, OH_Args.n))"):format(method))
		then
			return nil,
				("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
		end
	elseif not emitRemoteCall(body, state, remotePath, method, args, argCount, serialize) then
		return nil, ("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
	end

	local note = "-- Generated by Hydroxide RemoteSpy"

	if type(callInfo) == "table" and safeTypeof(callInfo.script) == "Instance" then
		local callingPath = getInstanceExpression(callInfo.script)

		if callingPath then
			note = note .. " | Source: " .. callingPath
		end
	end

	local header = { note }

	for _, warning in ipairs(state.warnings) do
		header[#header + 1] = "-- Warning: " .. warning
	end

	local generated = table.concat(header, "\n") .. "\n" .. table.concat(body, "\n")

	if #generated > state.maxOutputBytes then
		return nil, ("Generated script exceeded the configured output limit (%d bytes)."):format(state.maxOutputBytes)
	end

	local valid, validationError = validateGeneratedSource(generated, "@HydroxideRemoteReplay")

	if not valid then
		return nil, "Generated replay source did not compile: " .. tostring(validationError)
	end

	return generated
end

methods.buildRemoteScript = buildRemoteScript
methods.getReplayInstancePath = getInstanceExpression
methods.validateGeneratedSource = validateGeneratedSource
return methods
