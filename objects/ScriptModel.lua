local ScriptModel = {}
local CLOSED_ERROR = "Script inspector has been closed"
local SOURCE_MARKER = "\n-- ... source truncated by the configured safety limit ..."

local function isClosed(model)
	if not model._Destroyed and model._Runtime and model._Runtime.Exited then
		ScriptModel.destroy(model)
	end
	return model._Destroyed
end

local function boundedNumber(value, fallback, minimum, maximum)
	value = tonumber(value)
	if not value or value ~= value then
		value = fallback
	end
	return math.floor(math.max(minimum, math.min(maximum, value)))
end

local function sourceLimit(model, value)
	local settings = model._Runtime and model._Runtime.Settings or {}
	local fallback = boundedNumber(settings.MaxInspectorBytes or settings.maxInspectorBytes, 524288, 1024, 8388608)
	return boundedNumber(value, fallback, 1024, 8388608)
end

local function boundText(text, maximum, marker)
	if #text <= maximum then
		return text, true
	end
	local cut = math.max(0, maximum - #marker)
	-- Keep a valid UTF-8 source valid when a byte limit lands inside a character.
	while cut > 0 do
		local nextByte = text:byte(cut + 1)
		if not nextByte or nextByte < 128 or nextByte >= 192 then
			break
		end
		cut = cut - 1
	end
	return text:sub(1, cut) .. marker, false
end

local function errorText(value)
	local ok, text = pcall(tostring, value)
	return (boundText(ok and text or "Unable to format inspector error", 2048, "... [error truncated]"))
end

local function readValue(callback, argument, expectedType, failure)
	local ok, value, detail = pcall(callback, argument)
	if not ok then
		return nil, errorText(value)
	elseif type(value) == expectedType and (expectedType ~= "string" or value ~= "") then
		return value
	end
	return nil, errorText(type(detail) == "string" and detail or failure)
end

local function cacheLimits(model)
	local settings = model._Runtime and model._Runtime.Settings or {}
	return boundedNumber(settings.MaxFunctionSourceCacheEntries or settings.maxFunctionSourceCacheEntries, 16, 1, 128),
		boundedNumber(settings.MaxFunctionSourceCacheBytes or settings.maxFunctionSourceCacheBytes, 1048576, 32768, 8388608)
end

local function entryBytes(entry)
	return #(entry.Source or "") + #(entry.Error or "")
end

local function releaseEntry(entry)
	local budget, token = entry.Budget, entry.BudgetToken
	entry.Budget, entry.BudgetToken = nil, nil
	if budget and token then
		budget:Release(token, false)
	end
end

local function removeSource(model, target, expected, release)
	local entry = model.FunctionSources[target]
	if not entry or (expected and entry ~= expected) then
		return
	end
	model.FunctionSources[target] = nil
	model.FunctionSourceBytes = math.max(0, model.FunctionSourceBytes - entryBytes(entry))
	for index, key in ipairs(model.FunctionSourceOrder) do
		if key == target then
			table.remove(model.FunctionSourceOrder, index)
			break
		end
	end
	if release then
		releaseEntry(entry)
	else
		entry.Budget, entry.BudgetToken = nil, nil
	end
end

local function cacheSource(model, target, entry)
	local existing = model.FunctionSources[target]
	-- A slower, smaller request must not replace a more useful completed result.
	if existing and existing.Source and (existing.Complete or existing.Limit >= entry.Limit) then
		return
	end
	if existing then
		removeSource(model, target, existing, true)
	end
	local maximumEntries, maximumBytes = cacheLimits(model)
	local bytes = entryBytes(entry)
	if bytes > maximumBytes then
		return
	end
	local budget = model._Runtime and model._Runtime.FunctionSourceCache
	if budget and type(budget.Reserve) == "function" and type(budget.Release) == "function" then
		-- A shared budget must not keep an otherwise abandoned inspector alive.
		local owner = setmetatable({ model, target, entry }, { __mode = "v" })
		local token = budget:Reserve(bytes, function()
			if owner[1] and owner[2] and owner[3] then
				removeSource(owner[1], owner[2], owner[3], false)
			end
		end)
		if not token then
			return
		end
		entry.Budget, entry.BudgetToken = budget, token
	end
	model.FunctionSources[target] = entry
	model.FunctionSourceOrder[#model.FunctionSourceOrder + 1] = target
	model.FunctionSourceBytes = model.FunctionSourceBytes + bytes
	while #model.FunctionSourceOrder > maximumEntries or model.FunctionSourceBytes > maximumBytes do
		local oldest = model.FunctionSourceOrder[1]
		if model.FunctionSources[oldest] then
			removeSource(model, oldest, nil, true)
		else
			table.remove(model.FunctionSourceOrder, 1)
		end
	end
end

function ScriptModel.clearFunctionSourceCache(model)
	model._FunctionSourceGeneration = model._FunctionSourceGeneration + 1
	for _, entry in pairs(model.FunctionSources) do
		releaseEntry(entry)
	end
	model.FunctionSources = {}
	model.FunctionSourceOrder = {}
	model.FunctionSourceBytes = 0
end

function ScriptModel.destroy(model)
	if model._Destroyed then
		return
	end
	model._Destroyed = true
	ScriptModel.clearFunctionSourceCache(model)
	model._Runtime = nil
	model.Instance, model.Closure, model.Environment, model.Source = nil, nil, nil, nil
	model.Constants, model.Protos = {}, {}
	model.ClosureError, model.EnvironmentError, model.ConstantsError, model.ProtosError, model.SourceError = nil, nil, nil, nil, nil
	model.LoadedClosure, model.LoadedEnvironment, model.LoadedConstants, model.LoadedProtos, model.LoadedSource = false, false, false, false, false
	model.SourceLimit, model.SourceComplete = 0, false
end

local function saveResource(model, field, value, message)
	if isClosed(model) then
		return nil, CLOSED_ERROR
	end
	model["Loaded" .. field] = true
	model[field .. "Error"] = message
	if value ~= nil then
		model[field] = value
	end
	return value, message
end

local function loadResource(model, field, callback, expectedType, methodName, failure, needsClosure)
	if isClosed(model) then
		return nil, CLOSED_ERROR
	elseif model["Loaded" .. field] then
		return model[field .. "Error"] == nil and model[field] or nil, model[field .. "Error"]
	elseif type(callback) ~= "function" then
		return saveResource(model, field, nil, methodName .. " is not available in this executor")
	end
	local target = model.Instance
	if needsClosure then
		local closure, message = model:LoadClosure()
		if not closure then
			return saveResource(model, field, nil, message)
		end
		target = closure
	end
	local value, message = readValue(callback, target, expectedType, failure)
	if value == nil and expectedType == "table" and not isClosed(model) then
		model[field] = {}
	end
	return saveResource(model, field, value, message)
end

function ScriptModel.loadClosure(model)
	return loadResource(model, "Closure", getScriptClosure, "function", "getScriptClosure", model._Kind .. " closure was not returned")
end

function ScriptModel.loadConstants(model)
	return loadResource(model, "Constants", getConstants, "table", "getConstants", "Constants were not returned", true)
end

function ScriptModel.loadProtos(model)
	return loadResource(model, "Protos", getProtos, "table", "getProtos", "Protos were not returned", true)
end

function ScriptModel.loadEnvironment(model)
	if model._Kind ~= "Module" then
		return loadResource(model, "Environment", getSenv, "table", "getSenv", "Script environment was not returned")
	elseif isClosed(model) then
		return nil, CLOSED_ERROR
	elseif model.LoadedEnvironment then
		return model.EnvironmentError == nil and model.Environment or nil, model.EnvironmentError
	end
	local failures = {}
	-- getsenv is documented for modules; keep the distinct legacy fallback.
	for index = 1, 2 do
		local callback = getSenv
		if index == 2 then
			callback = getMenv
		end
		if type(callback) == "function" and (index == 1 or callback ~= getSenv) then
			local environment, message = readValue(callback, model.Instance, "table", "Module environment was not returned")
			if isClosed(model) or environment then
				return saveResource(model, "Environment", environment, message)
			end
			failures[#failures + 1] = (index == 1 and "getSenv: " or "getMenv: ") .. message
		end
	end
	if #failures > 0 then
		model.Environment = {}
	end
	return saveResource(model, "Environment", nil, #failures > 0 and errorText(table.concat(failures, "; "))
		or "getMenv/getSenv is not available in this executor")
end

function ScriptModel.decompile(model, target, maximumBytes)
	if isClosed(model) then
		return nil, CLOSED_ERROR
	end
	local maximum = sourceLimit(model, maximumBytes)
	local cached = target and model.FunctionSources[target] or nil
	if cached and (cached.Complete or cached.Limit >= maximum) then
		return cached.Source and (boundText(cached.Source, maximum, SOURCE_MARKER)) or nil, cached.Error
	elseif not target and model.LoadedSource and (model.SourceComplete or model.SourceLimit >= maximum) then
		return model.Source and (boundText(model.Source, maximum, SOURCE_MARKER)) or nil, model.SourceError
	end
	local generation = model._FunctionSourceGeneration
	local source, message
	if type(decompile) == "function" then
		source, message = readValue(decompile, target or model.Instance, "string", "Decompiler did not return text")
		if not source and not target and not isClosed(model) then
			local closure, closureError = model:LoadClosure()
			if closure then
				source, message = readValue(decompile, closure, "string", "Decompiler did not return text")
			elseif message == "Decompiler did not return text" then
				message = closureError or message
			else
				message = errorText(message .. "; closure: " .. (closureError or "unavailable"))
			end
		end
	else
		message = "decompile is not available in this executor"
	end
	if isClosed(model) then
		return nil, CLOSED_ERROR
	end
	local complete = true
	if source then
		source, complete = boundText(source, maximum, SOURCE_MARKER)
	end
	if target then
		if generation == model._FunctionSourceGeneration then
			cacheSource(model, target, { Source = source, Error = message, Limit = maximum, Complete = complete })
		end
	elseif not (model.Source and (model.SourceComplete or model.SourceLimit > maximum)) then
		model.Source, model.SourceError, model.SourceLimit = source, message, maximum
		model.SourceComplete, model.LoadedSource = complete, true
	end
	return source, message
end

function ScriptModel.create(kind)
	local Model = {
		loadClosure = ScriptModel.loadClosure,
		loadEnvironment = ScriptModel.loadEnvironment,
		loadConstants = ScriptModel.loadConstants,
		loadProtos = ScriptModel.loadProtos,
		decompile = ScriptModel.decompile,
		clearFunctionSourceCache = ScriptModel.clearFunctionSourceCache,
		destroy = ScriptModel.destroy,
	}
	function Model.new(instance, closure, environment)
		local validClosure, validEnvironment = type(closure) == "function", type(environment) == "table"
		return {
			Instance = instance,
			Closure = validClosure and closure or nil,
			Environment = validEnvironment and environment or nil,
			Constants = {}, Protos = {},
			SourceLimit = 0, SourceComplete = false,
			FunctionSources = {}, FunctionSourceOrder = {}, FunctionSourceBytes = 0,
			LoadedClosure = validClosure, LoadedEnvironment = validEnvironment,
			LoadedConstants = false, LoadedProtos = false, LoadedSource = false,
			LoadClosure = Model.loadClosure, LoadEnvironment = Model.loadEnvironment,
			LoadConstants = Model.loadConstants, LoadProtos = Model.loadProtos,
			Decompile = Model.decompile, ClearFunctionSourceCache = Model.clearFunctionSourceCache,
			Destroy = Model.destroy, _Kind = kind, _Destroyed = false, _FunctionSourceGeneration = 0,
			_Runtime = type(oh) == "table" and oh or nil,
		}
	end
	return Model
end

return ScriptModel
