local FunctionInspector = {}
local sourceCache = setmetatable({}, { __mode = "k" })
local sourceCacheOrder = {}
local sourceCacheBytes = 0

local function numberLimit(value, fallback, minimum, maximum)
	value = tonumber(value)

	if not value or value ~= value or math.abs(value) == math.huge then
		value = fallback
	end

	return math.max(minimum, math.min(maximum, math.floor(value)))
end

local function sourceCacheLimits()
	local settings = oh and oh.Settings or {}
	return numberLimit(settings.MaxFunctionSourceCacheEntries or settings.maxFunctionSourceCacheEntries, 64, 1, 256),
		numberLimit(settings.MaxFunctionSourceCacheBytes or settings.maxFunctionSourceCacheBytes, 2097152, 32768, 16777216)
end

local function sourceCacheEntryBytes(entry)
	return #(type(entry.Source) == "string" and entry.Source or "") + #(type(entry.Error) == "string" and entry.Error or "")
end

local function sharedSourceCacheBudget()
	local budget = oh and oh.FunctionSourceCache

	if budget and type(budget.Reserve) == "function" and type(budget.Release) == "function" then
		return budget
	end
end

local function removeCachedSource(func, expected, releaseBudget)
	local cached = sourceCache[func]

	if not cached or (expected and cached ~= expected) then
		return
	end

	sourceCache[func] = nil
	sourceCacheBytes = math.max(0, sourceCacheBytes - sourceCacheEntryBytes(cached))

	for index, cachedFunction in ipairs(sourceCacheOrder) do
		if cachedFunction == func then
			table.remove(sourceCacheOrder, index)
			break
		end
	end

	if releaseBudget and cached.BudgetToken then
		local budget = cached.Budget

		if budget then
			budget:Release(cached.BudgetToken, false)
		end
	end

	cached.BudgetToken = nil
	cached.Budget = nil
end

local function cacheSource(func, entry)
	local existing = sourceCache[func]

	if existing then
		removeCachedSource(func, existing, true)
	end

	local maximumEntries, maximumBytes = sourceCacheLimits()
	local entryBytes = sourceCacheEntryBytes(entry)

	if entryBytes > maximumBytes then
		return
	end

	local budget = sharedSourceCacheBudget()

	if budget then
		local references = setmetatable({ func, entry }, { __mode = "v" })
		local token = budget:Reserve(entryBytes, function()
			local target, cached = references[1], references[2]

			if target and cached then
				removeCachedSource(target, cached, false)
			end
		end)

		if not token then
			return
		end

		entry.BudgetToken = token
		entry.Budget = budget
	end

	sourceCache[func] = entry
	sourceCacheOrder[#sourceCacheOrder + 1] = func
	sourceCacheBytes = sourceCacheBytes + entryBytes

	while #sourceCacheOrder > maximumEntries or sourceCacheBytes > maximumBytes do
		local evictedFunction = sourceCacheOrder[1]
		local evicted = sourceCache[evictedFunction]

		if evicted then
			removeCachedSource(evictedFunction, evicted, true)
		else
			table.remove(sourceCacheOrder, 1)
		end
	end
end

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

local function boundedText(value, maximum)
	maximum = math.max(8, math.floor(tonumber(maximum) or 240))
	local text

	if type(value) == "string" then
		text = value
	else
		text = safeTostring(value)
	end

	if #text <= maximum then
		return text
	end

	return text:sub(1, maximum - 3) .. "..."
end

local function defaultSummary(value)
	local valueType = safeTypeof(value)

	if valueType == "string" then
		local truncated = #value > 120
		local text = value:sub(1, 120):gsub("[%c]", " ")
		return truncated and text:sub(1, 117) .. "..." or text
	elseif valueType == "table" then
		return "table"
	end

	return safeTostring(value)
end

local function appendBounded(lines, state, line)
	if state.Truncated then
		return false
	end

	line = safeTostring(line or "")
	local separator = #lines > 0 and 1 or 0
	local remaining = state.MaxBytes - state.Bytes - separator

	if #line > remaining then
		state.Truncated = true
		local marker = "... inspector output truncated by the configured safety limit ..."
		line = marker:sub(1, math.max(0, remaining))
	end

	if remaining >= 0 then
		state.Bytes = state.Bytes + #line + separator
		lines[#lines + 1] = line
	end

	return not state.Truncated
end

local function sortedEntries(values, limit)
	local entries = {}

	if type(values) ~= "table" then
		return entries, 0
	end

	local total = 0
	local hasMore = false

	for key, value in next, values do
		total = total + 1

		if total <= limit then
			entries[#entries + 1] = {
				Key = key,
				Value = value,
				Sort = boundedText(key, 240),
			}
		else
			hasMore = true
			break
		end
	end

	table.sort(entries, function(left, right)
		return left.Sort < right.Sort
	end)
	return entries, total, hasMore
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

	if ran and type(result) == "boolean" then
		return result
	end
end

local function inspectionIsActive(options)
	if oh and oh.Exited then
		return false
	end

	if type(options.IsAlive) ~= "function" then
		return true
	end

	local ran, active = pcall(options.IsAlive)
	return ran and active ~= false
end

local function boundSource(source, sourceLimit)
	if type(source) ~= "string" or #source <= sourceLimit then
		return source, true
	end

	local marker = "\n-- ... source truncated ..."
	return source:sub(1, math.max(0, sourceLimit - #marker)) .. marker, false
end

local function functionSource(func, options)
	local decompiler = options.Decompile or decompile
	local cacheAllowed = options.CacheSource ~= false and options.Decompile == nil
	local sourceLimit = numberLimit(options.MaxSourceBytes, 32768, 1024, 8388608)

	if options.IncludeSource == false then
		return nil, "skipped by the inspection work budget"
	elseif not inspectionIsActive(options) then
		return nil, "inspection was cancelled"
	end

	if type(decompiler) ~= "function" then
		return nil, "unavailable"
	end

	if cacheAllowed then
		local cached = sourceCache[func]

		if cached and (cached.Complete or (tonumber(cached.Limit) or 0) >= sourceLimit) then
			local source = cached.Source and select(1, boundSource(cached.Source, sourceLimit)) or nil
			return source, cached.Error
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

	local complete
	source, complete = boundSource(source, sourceLimit)
	sourceError = sourceError and boundedText(sourceError, 4096) or nil

	if not inspectionIsActive(options) then
		return nil, "inspection was cancelled"
	end

	if cacheAllowed then
		cacheSource(func, {
			Source = source,
			Error = sourceError,
			Limit = sourceLimit,
			Complete = complete or source == nil,
		})
	end

	return source, sourceError
end

local function describeFunctionInto(lines, state, func, options)
	if state.Truncated or not inspectionIsActive(options) then
		return
	end

	local summarize = options.Summarize or defaultSummary
	local getPath = options.GetPath
	local maxValues = numberLimit(options.MaxValues, 32, 1, 1000)
	local infoRan, info = pcall(getInfo, func)

	info = infoRan and type(info) == "table" and info or nil
	appendBounded(lines, state, "Function: " .. safeTostring(func))
	appendBounded(lines, state, "Name: " .. boundedText(info and info.name or "anonymous", 1024))
	appendBounded(lines, state, "Kind: " .. boundedText(info and info.what or "unknown", 120))
	appendBounded(lines, state, "Source: " .. boundedText(info and (info.short_src or info.source) or "unknown", 4096))
	appendBounded(lines, state, "Defined: " .. tostring(info and info.linedefined or "unknown"))
	appendBounded(lines, state, "Current line: " .. tostring(info and info.currentline or "unknown"))
	appendBounded(lines, state, "Declared upvalues: " .. tostring(info and info.nups or "unknown"))

	if state.Truncated then
		return
	end

	local luaClosure = callBoolean(isLClosure, func)
	local executorClosure = callBoolean(isXClosure, func)

	if luaClosure ~= nil then
		appendBounded(lines, state, "Closure type: " .. (luaClosure and "Lua" or "C"))
	end

	if executorClosure ~= nil then
		appendBounded(lines, state, "Origin: " .. (executorClosure and "executor" or "game"))
	end

	if state.Truncated then
		return
	end

	if type(getFunctionHash) == "function" then
		local hashRan, hash = pcall(getFunctionHash, func)

		if hashRan and hash ~= nil then
			appendBounded(lines, state, "Function hash: " .. safeTostring(hash))
		end
	end

	if state.Truncated then
		return
	end

	if not inspectionIsActive(options) then
		return
	end

	local environment, environmentError = functionEnvironment(func)
	local environmentScript = environment and rawget(environment, "script")

	if safeTypeof(environmentScript) == "Instance" and type(getPath) == "function" then
		local pathRan, path = pcall(getPath, environmentScript)
		appendBounded(lines, state, "Environment script: " .. tostring(pathRan and path or environmentScript))
	elseif environmentError then
		appendBounded(lines, state, "Environment: " .. environmentError)
	end

	if state.Truncated then
		return
	end

	local sections = {
		{ "Upvalues", getUpvalues },
		{ "Constants", getConstants },
		{ "Protos", getProtos },
	}

	for _, section in ipairs(sections) do
		if state.Truncated or not inspectionIsActive(options) then
			return
		end

		local title = section[1]
		local values, valuesError = safeFunctionTable(section[2], func)

		if values then
			local entries, total, hasMore = sortedEntries(values, maxValues)
			appendBounded(lines, state, hasMore and ("%s (%d+):"):format(title, total) or ("%s (%d):"):format(title, total))

			for _, entry in ipairs(entries) do
				local detail

				if title == "Protos" and type(entry.Value) == "function" then
					local protoRan, protoInfo = pcall(getInfo, entry.Value)
					detail = protoRan and protoInfo and protoInfo.name or "anonymous function"
				else
					local summarized, result = pcall(summarize, entry.Value)
					detail = summarized and result or defaultSummary(entry.Value)
				end

				if not appendBounded(lines, state, ("  [%s] %s"):format(entry.Sort, boundedText(detail, 512))) then
					break
				end
			end

			if hasMore then
				appendBounded(lines, state, "  ... more entries were not scanned")
			end
		else
			appendBounded(lines, state, title .. ": " .. tostring(valuesError))
		end
	end

	if environment then
		if state.Truncated or not inspectionIsActive(options) then
			return
		end

		local entries, total, hasMore = sortedEntries(environment, maxValues)
		appendBounded(
			lines,
			state,
			hasMore and ("Environment (%d+ keys):"):format(total) or ("Environment (%d keys):"):format(total)
		)

		for _, entry in ipairs(entries) do
			local summarized, result = pcall(summarize, entry.Value)
			local detail = summarized and result or defaultSummary(entry.Value)

			if not appendBounded(lines, state, ("  %s = %s"):format(entry.Sort, boundedText(detail, 512))) then
				break
			end
		end

		if hasMore then
			appendBounded(lines, state, "  ... more keys were not scanned")
		end
	end

	if state.Truncated or not inspectionIsActive(options) then
		return
	end

	local source, sourceError = functionSource(func, options)

	if source then
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

	if not inspectionIsActive(options) then
		return "Function inspection was cancelled."
	end

	local lines = {}
	local state = {
		Bytes = 0,
		MaxBytes = numberLimit(options.MaxOutputBytes, 131072, 1, 8388608),
		Truncated = false,
	}

	describeFunctionInto(lines, state, func, options)
	return table.concat(lines, "\n")
end

function FunctionInspector.DescribeStack(stack, options)
	options = type(options) == "table" and options or {}

	if not inspectionIsActive(options) then
		return "Function-stack inspection was cancelled."
	end

	if type(stack) ~= "table" or #stack == 0 then
		return "No function stack was captured for this call."
	end

	local lines = {}
	local state = {
		Bytes = 0,
		MaxBytes = numberLimit(options.MaxOutputBytes, 262144, 1, 8388608),
		Truncated = false,
	}
	local maxDetailedFrames = numberLimit(options.MaxDetailedFrames, 8, 1, 64)
	local maxDecompiledFrames = numberLimit(options.MaxDecompiledFrames, 3, 0, maxDetailedFrames)

	appendBounded(lines, state, ("FUNCTION CALL CHAIN (%d frames)"):format(#stack))
	appendBounded(lines, state, "Order: closest to the intercepted call -> outermost caller")
	appendBounded(lines, state, "")

	for index, frame in ipairs(stack) do
		if state.Truncated or not inspectionIsActive(options) then
			break
		end

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
				boundedText(name, 1024),
				boundedText(source, 4096):gsub("^[@=]", ""),
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
		if state.Truncated or not inspectionIsActive(options) then
			break
		elseif index > maxDetailedFrames then
			appendBounded(
				lines,
				state,
				("... %d additional frame%s remain in the call-chain summary above; detailed inspection is capped at %d ..."):format(
					#stack - maxDetailedFrames,
					#stack - maxDetailedFrames == 1 and "" or "s",
					maxDetailedFrames
				)
			)
			break
		end

		frame = type(frame) == "table" and frame or {}
		local func = frame.func or frame.Function
		local name = frame.name or frame.Name or "anonymous"
		local source = frame.shortSource or frame.short_src or frame.source or frame.Source or "unknown"
		local line = tonumber(frame.line or frame.currentline or frame.Line)
		appendBounded(lines, state, ("[%02d] %s"):format(index, boundedText(name, 1024)))
		appendBounded(
			lines,
			state,
			("Callsite: %s:%s"):format(boundedText(source, 4096):gsub("^[@=]", ""), line and math.floor(line) or "?")
		)

		if type(func) == "function" then
			local frameOptions = {}

			for name, value in pairs(options) do
				frameOptions[name] = value
			end

			frameOptions.IncludeSource = options.IncludeSource ~= false and index <= maxDecompiledFrames
			describeFunctionInto(lines, state, func, frameOptions)
		else
			appendBounded(lines, state, "Function object: unavailable")
		end

		appendBounded(lines, state, "")
		appendBounded(lines, state, index < #stack and "----------------------------------------" or "")
	end

	return table.concat(lines, "\n")
end

return FunctionInspector
