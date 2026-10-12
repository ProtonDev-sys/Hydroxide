local methods = {}

local function isBuffer(value)
	return type(value) == "buffer" or typeof(value) == "buffer"
end

local function tableToString(data, root, indents, seen, state)
	local rawType, valueType = type(data), typeof(data)
	if rawType == "userdata" or valueType ~= rawType or isBuffer(data) then
		return valueType == "Instance" and getInstancePath(data) or userdataValue(data)
	elseif rawType ~= "table" then
		-- Binary strings must use the same escaped literal path as top-level
		-- arguments; a failed UTF-8 conversion must never emit raw source.
		return dataToString(data)
	end

	indents, seen = indents or 1, seen or {}
	if not state then
		local settings = oh and oh.Settings or {}
		local function limit(name, fallback, minimum, maximum)
			local value = tonumber(settings[name])
			if not value or value ~= value or value == math.huge or value == -math.huge then
				value = fallback
			end
			return math.max(minimum, math.min(maximum, math.floor(value)))
		end
		state = {
			Entries = 0, Bytes = 0,
			MaxEntries = limit("MaxGeneratedTableEntries", 256, 8, 5000),
			MaxDepth = limit("MaxGeneratedTableDepth", 16, 1, 64),
			MaxBytes = limit("MaxGeneratedOutputBytes", 1048576, 16384, 8388608)
		}
	end
	if seen[data] then
		return "nil --[[ OH_CYCLIC_PROTECTION ]]"
	elseif indents > state.MaxDepth then
		return "nil --[[ table depth limit reached ]]"
	end

	seen[data] = true
	local parts, indent = {}, ("\t"):rep(indents)
	for key, value in next, data do
		if state.Entries >= state.MaxEntries or state.Bytes >= state.MaxBytes then
			parts[#parts + 1] = "nil --[[ table serialization limit reached ]]"
			break
		end
		state.Entries = state.Entries + 1
		local field
		if rawequal(key, root) or rawequal(value, root) then
			field = "nil --[[ OH_CYCLIC_PROTECTION ]]"
		else
			local keyText = tableToString(key, root or data, indents + 1, seen, state)
			if keyText:sub(1, 5) == "nil -" then
				field = "nil --[[ unsupported table key omitted ]]"
			else
				local valueText = tableToString(value, root or data, indents + 1, seen, state)
				field = ("[%s] = %s"):format(keyText, valueText)
			end
		end
		state.Bytes = state.Bytes + #field + #indent + 2
		if state.Bytes > state.MaxBytes then
			parts[#parts + 1] = "nil --[[ table serialization limit reached ]]"
			break
		end
		parts[#parts + 1] = field
	end
	seen[data] = nil
	if #parts == 0 then return "{}" end
	return "{\n" .. indent .. table.concat(parts, ",\n" .. indent)
		.. "\n" .. ("\t"):rep(indents - 1) .. "}"
end

local function compareTables(x, y)
	for index, value in next, x do
		if value ~= rawget(y, index) then
			return false
		end
	end

	for index in next, y do
		if rawget(x, index) == nil then
			return false
		end
	end

	return true
end

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

local function boundedNumber(options, name, fallback, minimum, maximum)
	local settings = type(oh) == "table" and type(oh.Settings) == "table" and oh.Settings or {}
	local lowerName = name:sub(1, 1):lower() .. name:sub(2)
	local value = tonumber(options[name] or options[lowerName] or settings[name] or settings[lowerName]) or fallback

	if value ~= value or value == math.huge or value == -math.huge then
		value = fallback
	end
	value = math.floor(value)
	return math.max(minimum, math.min(maximum, value))
end

local function scalarText(value)
	if type(dataToString) == "function" then
		local ran, result = pcall(dataToString, value)

		if ran and type(result) == "string" then
			return result
		end
	end

	local rawType = type(value)

	if rawType == "string" then
		return string.format("%q", value)
	elseif rawType == "nil" then
		return "nil"
	end

	return safeTostring(value)
end

local keyTypeOrder = {
	number = 1,
	string = 2,
	boolean = 3,
	Instance = 4,
	table = 5,
	userdata = 6,
	["function"] = 7,
	thread = 8,
}

local function keySortToken(value)
	local valueType = safeTypeof(value)
	local rank = keyTypeOrder[valueType] or keyTypeOrder[type(value)] or 99
	local body

	if type(value) == "number" then
		if value ~= value then
			body = "nan"
		elseif value == math.huge then
			body = "inf"
		elseif value == -math.huge then
			body = "-inf"
		else
			body = string.format("%+.17g", value)
		end
	else
		body = scalarText(value)
	end

	return string.format("%03d:%s", rank, body)
end

-- Formats captured values for the in-menu inspectors. Unlike tableToString,
-- this is deliberately bounded and labels shared/cyclic tables instead of
-- hiding their contents behind a one-line summary.
local function formatValueTree(value, options)
	options = type(options) == "table" and options or {}
	local maxDepth = boundedNumber(options, "MaxDepth", 8, 1, 32)
	local maxEntries = boundedNumber(options, "MaxEntries", 512, 1, 10000)
	local maxTableEntries = boundedNumber(options, "MaxTableEntries", 256, 1, 5000)
	local maxOutputBytes = boundedNumber(options, "MaxOutputBytes", 65536, 256, 1048576)
	local indentText = type(options.Indent) == "string" and options.Indent:sub(1, 16) or "  "
	local parts = {}
	local outputBytes = 0
	local stopped = false
	local seen = {}
	local nextTableId = 0
	local totalEntries = 0

	local function append(text)
		if stopped then
			return false
		end

		text = tostring(text or "")

		if outputBytes + #text > maxOutputBytes then
			local marker = "\n... <value output truncated>"
			local remaining = maxOutputBytes - outputBytes

			if remaining > 0 then
				parts[#parts + 1] = marker:sub(1, remaining)
				outputBytes = outputBytes + math.min(#marker, remaining)
			end

			stopped = true
			return false
		end

		outputBytes = outputBytes + #text
		parts[#parts + 1] = text
		return true
	end

	local renderValue

	local function isExpandableTable(candidate)
		if type(candidate) ~= "table" then
			return false
		end

		local candidateType = safeTypeof(candidate)
		return candidateType == "table" or candidateType == "SharedTable"
	end

	local function renderKey(key)
		if isExpandableTable(key) then
			local id = seen[key]
			return id and ("<table#%d>"):format(id) or "<table key>"
		end

		return scalarText(key)
	end

	local function readEntries(tableValue)
		local entries = {}
		local previous
		local truncated = false

		while #entries < maxTableEntries and totalEntries < maxEntries do
			local ran, key, child = pcall(next, tableValue, previous)

			if not ran then
				entries[#entries + 1] = {
					Error = "table iteration failed: " .. safeTostring(key),
					SortToken = "999:error",
					OriginalIndex = #entries + 1,
				}
				return entries, false
			elseif key == nil then
				return entries, false
			end

			totalEntries = totalEntries + 1
			entries[#entries + 1] = {
				Key = key,
				Value = child,
				SortToken = keySortToken(key),
				OriginalIndex = #entries + 1,
			}
			previous = key
		end

		local ran, nextKey = pcall(next, tableValue, previous)
		truncated = ran and nextKey ~= nil
		return entries, truncated
	end

	renderValue = function(current, depth, indentLevel)
		local rawType = type(current)
		local valueType = safeTypeof(current)

		if rawType ~= "table" or (valueType ~= "table" and valueType ~= "SharedTable") then
			return append(scalarText(current))
		end

		local existingId = seen[current]

		if existingId then
			return append(("<ref table#%d>"):format(existingId))
		elseif depth > maxDepth then
			return append("<table depth limit reached>")
		end

		nextTableId = nextTableId + 1
		local tableId = nextTableId
		seen[current] = tableId
		local entries, truncated = readEntries(current)

		table.sort(entries, function(left, right)
			if left.SortToken == right.SortToken then
				return left.OriginalIndex < right.OriginalIndex
			end

			return left.SortToken < right.SortToken
		end)

		if not append(("table#%d {"):format(tableId)) then
			return false
		elseif #entries == 0 and not truncated then
			return append("}")
		end

		local childIndent = indentText:rep(indentLevel + 1)
		local closingIndent = indentText:rep(indentLevel)

		for _, entry in ipairs(entries) do
			if not append("\n" .. childIndent) then
				return false
			elseif entry.Error then
				if not append("<" .. entry.Error .. ">") then
					return false
				end
			elseif not append("[" .. renderKey(entry.Key) .. "] = ") then
				return false
			elseif not renderValue(entry.Value, depth + 1, indentLevel + 1) then
				return false
			end
		end

		if truncated and not append("\n" .. childIndent .. "... <entry limit reached>") then
			return false
		end

		return append("\n" .. closingIndent .. "}")
	end

	renderValue(value, 1, 0)
	return table.concat(parts)
end

methods.tableToString = tableToString
methods.compareTables = compareTables
methods.formatValueTree = formatValueTree
return methods
