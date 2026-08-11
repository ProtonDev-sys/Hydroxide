local LocalScript = {}

local function unavailable(name)
	return nil, name .. " is not available in this executor"
end

local function normalizeSourceLimit(value)
	local settings = oh and oh.Settings or {}
	value = tonumber(value) or tonumber(settings.MaxInspectorBytes or settings.maxInspectorBytes) or 524288
	return math.max(1024, math.min(8388608, math.floor(value)))
end

local function boundSource(source, maximum)
	if type(source) ~= "string" or #source <= maximum then
		return source, true
	end

	local marker = "\n-- ... source truncated by the configured safety limit ..."
	return source:sub(1, math.max(0, maximum - #marker)) .. marker, false
end

local function functionCacheLimits()
	local settings = oh and oh.Settings or {}
	local entries = tonumber(settings.MaxFunctionSourceCacheEntries or settings.maxFunctionSourceCacheEntries) or 16
	local bytes = tonumber(settings.MaxFunctionSourceCacheBytes or settings.maxFunctionSourceCacheBytes) or 1048576
	return math.max(1, math.min(128, math.floor(entries))), math.max(32768, math.min(8388608, math.floor(bytes)))
end

local function functionCacheEntryBytes(entry)
	return #(type(entry.Source) == "string" and entry.Source or "") + #(type(entry.Error) == "string" and entry.Error or "")
end

local function sharedFunctionCacheBudget()
	local budget = oh and oh.FunctionSourceCache

	if budget and type(budget.Reserve) == "function" and type(budget.Release) == "function" then
		return budget
	end
end

local function removeFunctionSource(localScript, target, expected, releaseBudget)
	local cached = localScript.FunctionSources[target]

	if not cached or (expected and cached ~= expected) then
		return
	end

	localScript.FunctionSources[target] = nil
	localScript.FunctionSourceBytes = math.max(0, localScript.FunctionSourceBytes - functionCacheEntryBytes(cached))

	for index, cachedTarget in ipairs(localScript.FunctionSourceOrder) do
		if cachedTarget == target then
			table.remove(localScript.FunctionSourceOrder, index)
			break
		end
	end

	if releaseBudget and cached.BudgetToken then
		local budget = sharedFunctionCacheBudget()

		if budget then
			budget:Release(cached.BudgetToken, false)
		end
	end

	cached.BudgetToken = nil
end

local function cacheFunctionSource(localScript, target, entry)
	local existing = localScript.FunctionSources[target]

	if existing then
		removeFunctionSource(localScript, target, existing, true)
	end

	local maximumEntries, maximumBytes = functionCacheLimits()
	local entryBytes = functionCacheEntryBytes(entry)

	if entryBytes > maximumBytes then
		return
	end

	local budget = sharedFunctionCacheBudget()

	if budget then
		local token = budget:Reserve(entryBytes, function()
			removeFunctionSource(localScript, target, entry, false)
		end)

		if not token then
			return
		end

		entry.BudgetToken = token
	end

	localScript.FunctionSources[target] = entry
	localScript.FunctionSourceOrder[#localScript.FunctionSourceOrder + 1] = target
	localScript.FunctionSourceBytes = localScript.FunctionSourceBytes + entryBytes

	while #localScript.FunctionSourceOrder > maximumEntries or localScript.FunctionSourceBytes > maximumBytes do
		local evictedTarget = localScript.FunctionSourceOrder[1]
		local evicted = localScript.FunctionSources[evictedTarget]

		if evicted then
			removeFunctionSource(localScript, evictedTarget, evicted, true)
		else
			table.remove(localScript.FunctionSourceOrder, 1)
		end
	end
end

function LocalScript.clearFunctionSourceCache(localScript)
	while #localScript.FunctionSourceOrder > 0 do
		local target = localScript.FunctionSourceOrder[1]
		removeFunctionSource(localScript, target, nil, true)
	end
end

function LocalScript.new(instance, closure, scriptEnvironment)
	local localScript = {}

	localScript.Instance = instance
	localScript.Closure = closure
	localScript.ClosureError = nil
	localScript.Environment = scriptEnvironment
	localScript.EnvironmentError = nil
	localScript.Constants = {}
	localScript.ConstantsError = nil
	localScript.Protos = {}
	localScript.ProtosError = nil
	localScript.Source = nil
	localScript.SourceError = nil
	localScript.SourceLimit = 0
	localScript.SourceComplete = false
	localScript.FunctionSources = setmetatable({}, { __mode = "k" })
	localScript.FunctionSourceOrder = {}
	localScript.FunctionSourceBytes = 0
	localScript.LoadedClosure = closure ~= nil
	localScript.LoadedConstants = false
	localScript.LoadedProtos = false
	localScript.LoadedEnvironment = scriptEnvironment ~= nil
	localScript.LoadedSource = false
	localScript.LoadClosure = LocalScript.loadClosure
	localScript.LoadEnvironment = LocalScript.loadEnvironment
	localScript.LoadConstants = LocalScript.loadConstants
	localScript.LoadProtos = LocalScript.loadProtos
	localScript.Decompile = LocalScript.decompile
	localScript.ClearFunctionSourceCache = LocalScript.clearFunctionSourceCache

	return localScript
end

function LocalScript.loadClosure(localScript)
	if localScript.LoadedClosure then
		return localScript.Closure, localScript.ClosureError
	elseif type(getScriptClosure) ~= "function" then
		localScript.LoadedClosure = true
		localScript.ClosureError = "getScriptClosure is not available in this executor"
		return nil, localScript.ClosureError
	end

	local ran, closure = pcall(getScriptClosure, localScript.Instance)
	localScript.LoadedClosure = true

	if not ran or type(closure) ~= "function" then
		localScript.ClosureError = ran and "Script closure was not returned" or tostring(closure)
		return nil, localScript.ClosureError
	end

	localScript.Closure = closure
	localScript.ClosureError = nil
	return closure
end

function LocalScript.loadEnvironment(localScript)
	if localScript.LoadedEnvironment then
		if localScript.EnvironmentError then
			return nil, localScript.EnvironmentError
		end

		return localScript.Environment
	elseif type(getSenv) ~= "function" then
		localScript.LoadedEnvironment = true
		localScript.EnvironmentError = "getSenv is not available in this executor"
		return nil, localScript.EnvironmentError
	end

	local ran, environment = pcall(getSenv, localScript.Instance)

	if not ran or type(environment) ~= "table" then
		localScript.Environment = {}
		localScript.LoadedEnvironment = true
		localScript.EnvironmentError = ran and "Script environment was not returned" or tostring(environment)
		return nil, localScript.EnvironmentError
	end

	localScript.Environment = environment
	localScript.EnvironmentError = nil
	localScript.LoadedEnvironment = true
	return environment
end

function LocalScript.loadConstants(localScript)
	if localScript.LoadedConstants then
		if localScript.ConstantsError then
			return nil, localScript.ConstantsError
		end

		return localScript.Constants
	elseif type(getConstants) ~= "function" then
		localScript.LoadedConstants = true
		localScript.ConstantsError = "getConstants is not available in this executor"
		return nil, localScript.ConstantsError
	end

	local closure, closureError = localScript:LoadClosure()

	if not closure then
		localScript.LoadedConstants = true
		localScript.ConstantsError = closureError
		return nil, closureError
	end

	local ran, constants = pcall(getConstants, closure)

	if not ran or type(constants) ~= "table" then
		localScript.Constants = {}
		localScript.LoadedConstants = true
		localScript.ConstantsError = ran and "Constants were not returned" or tostring(constants)
		return nil, localScript.ConstantsError
	end

	localScript.Constants = constants
	localScript.ConstantsError = nil
	localScript.LoadedConstants = true
	return constants
end

function LocalScript.loadProtos(localScript)
	if localScript.LoadedProtos then
		if localScript.ProtosError then
			return nil, localScript.ProtosError
		end

		return localScript.Protos
	elseif type(getProtos) ~= "function" then
		localScript.LoadedProtos = true
		localScript.ProtosError = "getProtos is not available in this executor"
		return nil, localScript.ProtosError
	end

	local closure, closureError = localScript:LoadClosure()

	if not closure then
		localScript.LoadedProtos = true
		localScript.ProtosError = closureError
		return nil, closureError
	end

	local ran, protos = pcall(getProtos, closure)

	if not ran or type(protos) ~= "table" then
		localScript.Protos = {}
		localScript.LoadedProtos = true
		localScript.ProtosError = ran and "Protos were not returned" or tostring(protos)
		return nil, localScript.ProtosError
	end

	localScript.Protos = protos
	localScript.ProtosError = nil
	localScript.LoadedProtos = true
	return protos
end

function LocalScript.decompile(localScript, target, maximumBytes)
	local maximum = normalizeSourceLimit(maximumBytes)

	if target then
		local cached = localScript.FunctionSources[target]

		if cached and (cached.Complete or (tonumber(cached.Limit) or 0) >= maximum) then
			local source = cached.Source and select(1, boundSource(cached.Source, maximum)) or nil
			return source, cached.Error
		end
	elseif localScript.LoadedSource
		and (localScript.SourceComplete or (tonumber(localScript.SourceLimit) or 0) >= maximum)
	then
		local source = localScript.Source and select(1, boundSource(localScript.Source, maximum)) or nil
		return source, localScript.SourceError
	end

	if type(decompile) ~= "function" then
		local _, sourceError = unavailable("decompile")

		if target then
			cacheFunctionSource(localScript, target, {
				Source = nil,
				Error = sourceError,
				Limit = maximum,
				Complete = true,
			})
		else
			localScript.Source = nil
			localScript.SourceError = sourceError
			localScript.SourceLimit = maximum
			localScript.SourceComplete = true
			localScript.LoadedSource = true
		end

		return nil, sourceError
	end

	if target then
		local ran, source = pcall(decompile, target)
		local sourceError
		local complete = false

		if not ran or type(source) ~= "string" or source == "" then
			sourceError = ran and "Decompiler did not return text" or tostring(source)
			source = nil
		else
			source, complete = boundSource(source, maximum)
		end

		cacheFunctionSource(localScript, target, {
			Source = source,
			Error = sourceError,
			Limit = maximum,
			Complete = complete,
		})
		return source, sourceError
	end

	local ran, source = pcall(decompile, localScript.Instance)

	if ran and type(source) == "string" and source ~= "" then
		local complete
		source, complete = boundSource(source, maximum)
		localScript.LoadedSource = true
		localScript.Source = source
		localScript.SourceError = nil
		localScript.SourceLimit = maximum
		localScript.SourceComplete = complete
		return source
	end

	local closure, closureError = localScript:LoadClosure()

	if not closure then
		localScript.LoadedSource = true
		localScript.SourceError = closureError or (ran and "Decompiler did not return text" or tostring(source))
		localScript.SourceLimit = maximum
		localScript.SourceComplete = true
		return nil, localScript.SourceError
	end

	ran, source = pcall(decompile, closure)

	if ran and type(source) == "string" and source ~= "" then
		local complete
		source, complete = boundSource(source, maximum)
		localScript.LoadedSource = true
		localScript.Source = source
		localScript.SourceError = nil
		localScript.SourceLimit = maximum
		localScript.SourceComplete = complete
		return source
	end

	localScript.LoadedSource = true
	localScript.SourceError = ran and "Decompiler did not return text" or tostring(source)
	localScript.SourceLimit = maximum
	localScript.SourceComplete = true
	return nil, localScript.SourceError
end

return LocalScript
