local FunctionInspector = {}
local sourceCache = setmetatable({}, { __mode = "k" })
local sourceCacheOrder = {}
local sourceCacheBytes = 0

local function sourceCacheLimits()
	local settings = oh and oh.Settings or {}
	local entries = tonumber(settings.MaxFunctionSourceCacheEntries or settings.maxFunctionSourceCacheEntries) or 64
	local bytes = tonumber(settings.MaxFunctionSourceCacheBytes or settings.maxFunctionSourceCacheBytes) or 2097152
	return math.max(1, math.min(256, math.floor(entries))), math.max(32768, math.min(16777216, math.floor(bytes)))
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
		local budget = sharedSourceCacheBudget()

		if budget then
			budget:Release(cached.BudgetToken, false)
		end
	end

	cached.BudgetToken = nil
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
		local token = budget:Reserve(entryBytes, function()
			removeCachedSource(func, entry, false)
		end)

		if not token then
			return
		end

		entry.BudgetToken = token
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
	return ran and type(result) == "boolean" and result or nil
end

local function inspectionIsActive(options)
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
	local sourceLimit = math.max(1024, math.floor(tonumber(options.MaxSourceBytes) or 32768))

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
	local maxValues = math.max(1, math.floor(tonumber(options.MaxValues) or 32))
	local infoRan, info = pcall(getInfo, func)

	info = infoRan and type(info) == "table" and info or nil
	appendBounded(lines, state, "Function: " .. safeTostring(func))
	appendBounded(lines, state, "Name: " .. tostring(info and info.name or "anonymous"))
	appendBounded(lines, state, "Kind: " .. tostring(info and info.what or "unknown"))
	appendBounded(lines, state, "Source: " .. tostring(info and (info.short_src or info.source) or "unknown"))
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
		MaxBytes = math.max(8192, math.floor(tonumber(options.MaxOutputBytes) or 131072)),
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
		MaxBytes = math.max(16384, math.floor(tonumber(options.MaxOutputBytes) or 262144)),
		Truncated = false,
	}
	local maxDetailedFrames = math.max(1, math.floor(tonumber(options.MaxDetailedFrames) or 8))
	local maxDecompiledFrames = math.max(0, math.floor(tonumber(options.MaxDecompiledFrames) or 3))

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
		appendBounded(lines, state, ("[%02d] %s"):format(index, tostring(name)))
		appendBounded(
			lines,
			state,
			("Callsite: %s:%s"):format(tostring(source):gsub("^[@=]", ""), line and math.floor(line) or "?")
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
