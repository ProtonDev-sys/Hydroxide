local FunctionInspector = {}
local sourceCache = setmetatable({}, { __mode = "k" })

local function safeTypeof(value)
	if type(typeof) == "function" then
		local ran, valueType = pcall(typeof, value)
		return ran and valueType or type(value)
	end

	return type(value)
end

local function safeTostring(value)
	local ran, result = pcall(tostring, value)
	return ran and result or "<unprintable>"
end

local function defaultSummary(value)
	local valueType = safeTypeof(value)

	if valueType == "string" then
		local text = safeTostring(value):gsub("[%c]", " ")
		return #text > 120 and text:sub(1, 117) .. "..." or text
	elseif valueType == "table" then
		return "table"
	end

	return safeTostring(value)
end

local function appendBounded(lines, state, line)
	line = tostring(line or "")

	if state.Bytes + #line + 1 > state.MaxBytes then
		if not state.Truncated then
			state.Truncated = true
			lines[#lines + 1] = "... inspector output truncated by the configured safety limit ..."
		end

		return false
	end

	state.Bytes = state.Bytes + #line + 1
	lines[#lines + 1] = line
	return true
end

local function sortedEntries(values, limit)
	local entries = {}

	if type(values) ~= "table" then
		return entries, 0
	end

	local total = 0

	for key, value in next, values do
		total = total + 1

		if #entries < limit then
			entries[#entries + 1] = {
				Key = key,
				Value = value,
				Sort = safeTostring(key),
			}
		end
	end

	table.sort(entries, function(left, right)
		return left.Sort < right.Sort
	end)
	return entries, total
end

local function safeFunctionTable(method, func)
	if type(method) ~= "function" then
		return nil, "unavailable"
	end

	local ran, values = pcall(method, func)

	if ran and type(values) == "table" then
		return values
	end

	return nil, ran and "not returned" or safeTostring(values)
end

local function functionEnvironment(func)
	if type(getfenv) ~= "function" then
		return nil, "getfenv unavailable"
	end

	local ran, environment = pcall(getfenv, func)

	if ran and type(environment) == "table" then
		return environment
	end

	return nil, ran and "environment not returned" or safeTostring(environment)
end

local function callBoolean(method, func)
	if type(method) ~= "function" then
		return nil
	end

	local ran, result = pcall(method, func)
	return ran and type(result) == "boolean" and result or nil
end

local function functionSource(func, options)
	local decompiler = options.Decompile or decompile
	local cacheAllowed = options.CacheSource ~= false and options.Decompile == nil

	if type(decompiler) ~= "function" then
		return nil, "unavailable"
	end

	if cacheAllowed then
		local cached = sourceCache[func]

		if cached then
			return cached.Source, cached.Error
		end
	end

	local ran, source, sourceError = pcall(decompiler, func)

	if not ran then
		sourceError = safeTostring(source)
		source = nil
	elseif type(source) ~= "string" or source == "" then
		sourceError = sourceError or "no source returned"
		source = nil
	end

	if cacheAllowed then
		sourceCache[func] = {
			Source = source,
			Error = sourceError,
		}
	end

	return source, sourceError
end

local function describeFunctionInto(lines, state, func, options)
	local summarize = options.Summarize or defaultSummary
	local getPath = options.GetPath
	local maxValues = math.max(1, math.floor(tonumber(options.MaxValues) or 32))
	local sourceLimit = math.max(1024, math.floor(tonumber(options.MaxSourceBytes) or 32768))
	local infoRan, info = pcall(getInfo, func)

	info = infoRan and type(info) == "table" and info or nil
	appendBounded(lines, state, "Function: " .. safeTostring(func))
	appendBounded(lines, state, "Name: " .. tostring(info and info.name or "anonymous"))
	appendBounded(lines, state, "Kind: " .. tostring(info and info.what or "unknown"))
	appendBounded(lines, state, "Source: " .. tostring(info and (info.short_src or info.source) or "unknown"))
	appendBounded(lines, state, "Defined: " .. tostring(info and info.linedefined or "unknown"))
	appendBounded(lines, state, "Current line: " .. tostring(info and info.currentline or "unknown"))
	appendBounded(lines, state, "Declared upvalues: " .. tostring(info and info.nups or "unknown"))

	local luaClosure = callBoolean(isLClosure, func)
	local executorClosure = callBoolean(isXClosure, func)

	if luaClosure ~= nil then
		appendBounded(lines, state, "Closure type: " .. (luaClosure and "Lua" or "C"))
	end

	if executorClosure ~= nil then
		appendBounded(lines, state, "Origin: " .. (executorClosure and "executor" or "game"))
	end

	if type(getFunctionHash) == "function" then
		local hashRan, hash = pcall(getFunctionHash, func)

		if hashRan and hash ~= nil then
			appendBounded(lines, state, "Function hash: " .. safeTostring(hash))
		end
	end

	local environment, environmentError = functionEnvironment(func)
	local environmentScript = environment and rawget(environment, "script")

	if safeTypeof(environmentScript) == "Instance" and type(getPath) == "function" then
		local pathRan, path = pcall(getPath, environmentScript)
		appendBounded(lines, state, "Environment script: " .. tostring(pathRan and path or environmentScript))
	elseif environmentError then
		appendBounded(lines, state, "Environment: " .. environmentError)
	end

	local sections = {
		{ "Upvalues", getUpvalues },
		{ "Constants", getConstants },
		{ "Protos", getProtos },
	}

	for _, section in ipairs(sections) do
		local title = section[1]
		local values, valuesError = safeFunctionTable(section[2], func)

		if values then
			local entries, total = sortedEntries(values, maxValues)
			appendBounded(lines, state, ("%s (%d):"):format(title, total))

			for _, entry in ipairs(entries) do
				local detail

				if title == "Protos" and type(entry.Value) == "function" then
					local protoRan, protoInfo = pcall(getInfo, entry.Value)
					detail = protoRan and protoInfo and protoInfo.name or "anonymous function"
				else
					local summarized, result = pcall(summarize, entry.Value)
					detail = summarized and result or defaultSummary(entry.Value)
				end

				if not appendBounded(lines, state, ("  [%s] %s"):format(entry.Sort, tostring(detail))) then
					break
				end
			end

			if total > #entries then
				appendBounded(lines, state, ("  ... %d more"):format(total - #entries))
			end
		else
			appendBounded(lines, state, title .. ": " .. tostring(valuesError))
		end
	end

	if environment then
		local entries, total = sortedEntries(environment, maxValues)
		appendBounded(lines, state, ("Environment (%d keys):"):format(total))

		for _, entry in ipairs(entries) do
			local summarized, result = pcall(summarize, entry.Value)
			local detail = summarized and result or defaultSummary(entry.Value)

			if not appendBounded(lines, state, ("  %s = %s"):format(entry.Sort, tostring(detail))) then
				break
			end
		end

		if total > #entries then
			appendBounded(lines, state, ("  ... %d more"):format(total - #entries))
		end
	end

	local source, sourceError = functionSource(func, options)

	if source then
		if #source > sourceLimit then
			source = source:sub(1, sourceLimit) .. "\n-- ... source truncated ..."
		end

		appendBounded(lines, state, "")
		appendBounded(lines, state, "-- Decompiled source")
		appendBounded(lines, state, source)
	else
		appendBounded(lines, state, "Decompiler: " .. tostring(sourceError or "unavailable"))
	end
end

function FunctionInspector.DescribeFunction(func, options)
	if type(func) ~= "function" then
		return "No Lua function object was captured."
	end

	options = type(options) == "table" and options or {}
	local lines = {}
	local state = {
		Bytes = 0,
		MaxBytes = math.max(8192, math.floor(tonumber(options.MaxOutputBytes) or 131072)),
		Truncated = false,
	}

	describeFunctionInto(lines, state, func, options)
	return table.concat(lines, "\n")
end

function FunctionInspector.DescribeStack(stack, options)
	options = type(options) == "table" and options or {}

	if type(stack) ~= "table" or #stack == 0 then
		return "No function stack was captured for this call."
	end

	local lines = {}
	local state = {
		Bytes = 0,
		MaxBytes = math.max(16384, math.floor(tonumber(options.MaxOutputBytes) or 262144)),
		Truncated = false,
	}

	appendBounded(lines, state, ("FUNCTION CALL CHAIN (%d frames)"):format(#stack))
	appendBounded(lines, state, "Order: closest to the intercepted call -> outermost caller")
	appendBounded(lines, state, "")

	for index, frame in ipairs(stack) do
		frame = type(frame) == "table" and frame or {}
		local name = frame.name or frame.Name or "anonymous"
		local source = frame.shortSource or frame.short_src or frame.source or frame.Source or "unknown"
		local line = tonumber(frame.line or frame.currentline or frame.Line)
		local func = frame.func or frame.Function
		appendBounded(
			lines,
			state,
			("%02d  %s  %s:%s%s"):format(
				index,
				tostring(name),
				tostring(source):gsub("^[@=]", ""),
				line and math.floor(line) or "?",
				type(func) == "function" and ("  [" .. safeTostring(func) .. "]") or ""
			)
		)

		if index < #stack then
			appendBounded(lines, state, "    ->")
		end
	end

	appendBounded(lines, state, "")
	appendBounded(lines, state, "DETAILED FRAME INSPECTION")
	appendBounded(lines, state, "")

	for index, frame in ipairs(stack) do
		if state.Truncated then
			break
		end

		frame = type(frame) == "table" and frame or {}
		local func = frame.func or frame.Function
		local name = frame.name or frame.Name or "anonymous"
		local source = frame.shortSource or frame.short_src or frame.source or frame.Source or "unknown"
		local line = tonumber(frame.line or frame.currentline or frame.Line)
		appendBounded(lines, state, ("[%02d] %s"):format(index, tostring(name)))
		appendBounded(
			lines,
			state,
			("Callsite: %s:%s"):format(tostring(source):gsub("^[@=]", ""), line and math.floor(line) or "?")
		)

		if type(func) == "function" then
			describeFunctionInto(lines, state, func, options)
		else
			appendBounded(lines, state, "Function object: unavailable")
		end

		appendBounded(lines, state, "")
		appendBounded(lines, state, index < #stack and "----------------------------------------" or "")
	end

	return table.concat(lines, "\n")
end

return FunctionInspector
