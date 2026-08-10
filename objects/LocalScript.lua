local LocalScript = {}

local function unavailable(name)
	return nil, name .. " is not available in this executor"
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
	localScript.FunctionSources = setmetatable({}, { __mode = "k" })
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

function LocalScript.decompile(localScript, target)
	if type(decompile) ~= "function" then
		return unavailable("decompile")
	end

	if target then
		local cached = localScript.FunctionSources[target]

		if cached then
			return cached.Source, cached.Error
		end

		local ran, source = pcall(decompile, target)
		local sourceError

		if not ran or type(source) ~= "string" or source == "" then
			sourceError = ran and "Decompiler did not return text" or tostring(source)
			source = nil
		end

		localScript.FunctionSources[target] = {
			Source = source,
			Error = sourceError,
		}
		return source, sourceError
	elseif localScript.LoadedSource then
		return localScript.Source, localScript.SourceError
	end

	local ran, source = pcall(decompile, localScript.Instance)

	if ran and type(source) == "string" and source ~= "" then
		localScript.LoadedSource = true
		localScript.Source = source
		localScript.SourceError = nil
		return source
	end

	local closure, closureError = localScript:LoadClosure()

	if not closure then
		localScript.LoadedSource = true
		localScript.SourceError = closureError or (ran and "Decompiler did not return text" or tostring(source))
		return nil, localScript.SourceError
	end

	ran, source = pcall(decompile, closure)

	if ran and type(source) == "string" and source ~= "" then
		localScript.LoadedSource = true
		localScript.Source = source
		localScript.SourceError = nil
		return source
	end

	localScript.LoadedSource = true
	localScript.SourceError = ran and "Decompiler did not return text" or tostring(source)
	return nil, localScript.SourceError
end

return LocalScript
