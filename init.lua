local environment = assert(getgenv, "Hydroxide requires getgenv")()
local config = type(environment.HydroxideConfig) == "table" and environment.HydroxideConfig or {}
local web = config.web ~= false
local user = config.owner or "ProtonDev-sys"
local repository = config.repository or "Hydroxide"
local branch = config.branch or "main"

assert(type(user) == "string" and user:match("^[%w_-]+$"), "Invalid Hydroxide repository owner")
assert(
	type(repository) == "string" and repository:match("^[%w_.-]+$") and repository ~= "." and repository ~= "..",
	"Invalid Hydroxide repository name"
)
assert(type(branch) == "string" and #branch > 0 and #branch <= 255, "Invalid Hydroxide branch or commit")

local previousRuntime = environment.oh

if type(previousRuntime) == "table" and type(previousRuntime.Exit) == "function" then
	assert(previousRuntime.Exit() ~= false, "Hydroxide could not finish closing its previous session; retry after cleanup")
end

local HttpService = game:GetService("HttpService")
local importCache = {}
local publishedGlobals = {}
local originalGlobals = {}
local runtime
local sourceCache = {}
local loadingSources = {}
local loadingModules = {}
local pack = table.pack or function(...)
	return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack

local function numberSetting(name, defaultValue, minimum, maximum)
	local value = tonumber(config[name])

	if not value or value ~= value or value == math.huge or value == -math.huge then
		value = defaultValue
	end

	value = math.floor(value)
	return math.max(minimum, math.min(maximum, value))
end

local runtimeSettings = {
	CaptureExecutorCalls = config.captureExecutorCalls ~= false,
	CaptureCallStacks = config.captureCallStacks ~= false,
	MaxStackFrames = numberSetting("maxStackFrames", 24, 1, 64),
	MaxStackCapturesPerSecond = numberSetting("maxStackCapturesPerSecond", 60, 1, 1000),
	MaxRemoteLogs = numberSetting("maxRemoteLogs", 500, 25, 5000),
	MaxClosureLogs = numberSetting("maxClosureLogs", 500, 25, 5000),
	MaxRenderedLogs = numberSetting("maxRenderedLogs", 100, 10, 500),
	MaxArgumentPreviewLength = numberSetting("maxArgumentPreviewLength", 240, 40, 2000),
	MaxHexBytes = numberSetting("maxHexBytes", 512, 32, 8192),
	MaxConcurrentImports = numberSetting("maxConcurrentImports", 6, 1, 12),
	MaxGeneratedTableEntries = numberSetting("maxGeneratedTableEntries", 256, 8, 5000),
	MaxGeneratedTables = numberSetting("maxGeneratedTables", 512, 8, 5000),
	MaxGeneratedTableDepth = numberSetting("maxGeneratedTableDepth", 16, 1, 64),
	MaxGeneratedStringBytes = numberSetting("maxGeneratedStringBytes", 65536, 256, 1048576),
	MaxGeneratedBufferBytes = numberSetting("maxGeneratedBufferBytes", 65536, 256, 1048576),
	MaxGeneratedOutputBytes = numberSetting("maxGeneratedOutputBytes", 1048576, 16384, 8388608),
	MaxValueViewDepth = numberSetting("maxValueViewDepth", 8, 1, 32),
	MaxValueViewEntries = numberSetting("maxValueViewEntries", 512, 1, 10000),
	MaxValueViewTableEntries = numberSetting("maxValueViewTableEntries", 256, 1, 5000),
	MaxValueViewBytes = numberSetting("maxValueViewBytes", 65536, 1024, 1048576),
	MaxInspectorBytes = numberSetting("maxInspectorBytes", 524288, 8192, 8388608),
	MaxFunctionSourceCacheEntries = numberSetting("maxFunctionSourceCacheEntries", 64, 1, 256),
	MaxFunctionSourceCacheBytes = numberSetting("maxFunctionSourceCacheBytes", 2097152, 32768, 16777216),
	MaxConditionBufferBytes = numberSetting("maxConditionBufferBytes", 4096, 64, 65536),
	MaxCapturedCallBytes = numberSetting("maxCapturedCallBytes", 262144, 4096, 8388608),
	MaxCapturedArguments = numberSetting("maxCapturedArguments", 128, 8, 1024),
	MaxRemoteHistoryBytes = numberSetting("maxRemoteHistoryBytes", 16777216, 65536, 268435456),
	MaxClosureHistoryBytes = numberSetting("maxClosureHistoryBytes", 16777216, 65536, 268435456),
	MaxScriptRows = numberSetting("maxScriptRows", 750, 50, 2000),
	MaxModuleRows = numberSetting("maxModuleRows", 750, 50, 2000),
	MaxModuleFunctions = numberSetting("maxModuleFunctions", 32, 1, 128),
	-- Explicit zero retains snapshots until Clear; the default bounds memory.
	MaxRakNetLogs = numberSetting("maxRakNetLogs", 500, 0, 5000),
	MaxRenderedRakNetLogs = numberSetting("maxRenderedRakNetLogs", 100, 10, 500),
	MaxRakNetPacketBytes = numberSetting("maxRakNetPacketBytes", 65536, 256, 16777216),
	MaxRakNetHistoryBytes = numberSetting("maxRakNetHistoryBytes", 16777216, 0, 67108864),
	MaxRakNetGeneratedOutputBytes = numberSetting("maxRakNetGeneratedOutputBytes", 1048576, 1024, 8388608),
}

local function pick(...)
	for index = 1, select("#", ...) do
		local value = select(index, ...)

		if type(value) == "function" then
			return value
		end
	end
end

local function hasMethods(methods)
	for name in pairs(methods) do
		if type(environment[name]) ~= "function" then
			return false
		end
	end

	return true
end

local function useMethods(module)
	for name, method in pairs(module) do
		if method ~= nil then
			if publishedGlobals[name] == nil then
				originalGlobals[name] = { Value = environment[name] }
			end
			publishedGlobals[name] = method
			environment[name] = method
		end
	end
end

local function makeSetReadOnly()
	if type(setreadonly) == "function" then
		return setreadonly
	elseif type(makereadonly) == "function" and type(makewritable) == "function" then
		return function(target, readonly)
			if readonly and makereadonly then
				return makereadonly(target)
			elseif not readonly and makewritable then
				return makewritable(target)
			end
		end
	elseif type(make_readonly) == "function" and type(make_writeable) == "function" then
		return function(target, readonly)
			if readonly and make_readonly then
				return make_readonly(target)
			elseif not readonly and make_writeable then
				return make_writeable(target)
			end
		end
	end
end

local function makeIsLClosure()
	return pick(islclosure, is_l_closure, iscclosure and function(closure)
		return not iscclosure(closure)
	end)
end

local function makeHookMetaMethod(getMetatable)
	local rawHookMetaMethod = pick(hookmetamethod, environment.hookmetamethod)

	if rawHookMetaMethod then
		return rawHookMetaMethod
	end

	local rawHookFunction = pick(hookfunction, detour_function)

	if rawHookFunction and getMetatable then
		return function(object, method, hook)
			local metatable = getMetatable(object)
			local target = metatable and metatable[method]

			if not target then
				return nil
			end

			return rawHookFunction(target, hook)
		end
	end
end

local function getLibrary(name, fallback)
	local value = environment[name]
	return type(value) == "table" and value or type(fallback) == "table" and fallback or {}
end

local rawGetMetatable = pick(getrawmetatable, debug.getmetatable)
local othLibrary = getLibrary("oth", oth)
local httpLibrary = getLibrary("http", http)
local raknetLibrary = getLibrary("raknet", raknet)
local cryptLibrary = getLibrary("crypt", crypt)
local hashContent = pick(cryptLibrary.hash)
local canonicalMethods = {
	checkcaller = pick(checkcaller, environment.checkcaller),
	newcclosure = pick(newcclosure, environment.newcclosure),
	hookfunction = pick(hookfunction, detour_function, environment.hookfunction),
	restorefunction = pick(restorefunction, environment.restorefunction),
	decompile = pick(decompile, environment.decompile),
	filtergc = pick(filtergc, environment.filtergc),
	getgc = pick(getgc, get_gc_objects, environment.getgc),
	getfunctionhash = pick(getfunctionhash, getFunctionHash, environment.getfunctionhash, environment.getFunctionHash),
	getcallstack = pick(debug.getcallstack, getcallstack, environment.getcallstack),
	getinfo = pick(debug.getinfo, getinfo),
	getsenv = pick(getsenv, environment.getsenv),
	getmenv = pick(getmenv, environment.getmenv, getsenv, environment.getsenv),
	gettenv = pick(gettenv, environment.gettenv),
	getthreadidentity = pick(
		getthreadidentity,
		getidentity,
		getthreadcontext,
		get_thread_identity,
		get_thread_context,
		syn and syn.get_thread_identity
	),
	getconnections = pick(getconnections, get_signal_cons),
	getscriptbytecode = pick(getscriptbytecode, environment.getscriptbytecode),
	getscriptclosure = pick(getscriptclosure, get_script_function),
	getscriptfromthread = pick(getscriptfromthread, environment.getscriptfromthread),
	getrunningscripts = pick(getrunningscripts, environment.getrunningscripts),
	getscripthash = pick(getscripthash, environment.getscripthash),
	getscripts = pick(getscripts, environment.getscripts),
	getnamecallmethod = pick(getnamecallmethod, get_namecall_method),
	getcallingscript = pick(getcallingscript, get_calling_script),
	getloadedmodules = pick(getloadedmodules, get_loaded_modules),
	getconstants = pick(debug.getconstants, getconstants, getconsts),
	getupvalues = pick(debug.getupvalues, getupvalues, getupvals),
	getprotos = pick(debug.getprotos, getprotos),
	getstack = pick(debug.getstack, getstack),
	getconstant = pick(debug.getconstant, getconstant, getconst),
	getupvalue = pick(debug.getupvalue, getupvalue, getupval),
	getproto = pick(debug.getproto, getproto),
	getrawmetatable = rawGetMetatable,
	gethui = pick(gethui, get_hidden_gui),
	setclipboard = pick(setclipboard, writeclipboard),
	setconstant = pick(debug.setconstant, setconstant, setconst),
	setthreadidentity = pick(
		setthreadidentity,
		setidentity,
		setthreadcontext,
		set_thread_identity,
		set_thread_context,
		syn and syn.set_thread_identity
	),
	setupvalue = pick(debug.setupvalue, setupvalue, setupval),
	setstack = pick(debug.setstack, setstack),
	setreadonly = makeSetReadOnly(),
	islclosure = makeIsLClosure(),
	isreadonly = pick(isreadonly, is_readonly),
	isexecutorclosure = pick(
		isexecutorclosure,
		is_synapse_function,
		issentinelclosure,
		is_protosmasher_closure,
		is_sirhurt_closure,
		iselectronfunction,
		istempleclosure,
		checkclosure
	),
	hookmetamethod = nil,
	readfile = readfile,
	writefile = writefile,
	makefolder = makefolder,
	isfolder = isfolder,
	isfile = isfile,
	httpget = pick(httpget, environment.httpget, environment.HttpGet),
	request = pick(request, http_request, httpLibrary and httpLibrary.request, syn and syn.request),
	identifyexecutor = pick(identifyexecutor, getexecutorname),
	oth_hook = othLibrary and othLibrary.hook,
	oth_unhook = othLibrary and othLibrary.unhook,
	oth_get_root_callback = othLibrary and othLibrary.get_root_callback,
	oth_get_original_thread = othLibrary and othLibrary.get_original_thread,
	oth_is_hook_thread = othLibrary and othLibrary.is_hook_thread,
	raknet_add_send_hook = raknetLibrary and raknetLibrary.add_send_hook,
	raknet_remove_send_hook = raknetLibrary and raknetLibrary.remove_send_hook,
	raknet_add_receive_hook = raknetLibrary and raknetLibrary.add_receive_hook,
	raknet_remove_receive_hook = raknetLibrary and raknetLibrary.remove_receive_hook,
	raknet_send = raknetLibrary and raknetLibrary.send,
}

canonicalMethods.hookmetamethod = makeHookMetaMethod(canonicalMethods.getrawmetatable)

local function getConstantCompat(closure, index)
	local target = type(closure) == "table" and closure.Data or closure

	if not canonicalMethods.getconstant then
		if canonicalMethods.getconstants then
			local constants = canonicalMethods.getconstants(target)
			return constants and constants[index]
		end

		return nil
	end

	return canonicalMethods.getconstant(target, index)
end

local function getUpvalueCompat(closure, index)
	local target = type(closure) == "table" and closure.Data or closure

	if canonicalMethods.getupvalue then
		return canonicalMethods.getupvalue(target, index)
	end
end

local function getUpvaluesCompat(closure)
	local target = type(closure) == "table" and closure.Data or closure

	if canonicalMethods.getupvalues then
		return canonicalMethods.getupvalues(target)
	end

	return {}
end

local function getConstantsCompat(closure)
	local target = type(closure) == "table" and closure.Data or closure

	if canonicalMethods.getconstants then
		return canonicalMethods.getconstants(target)
	end

	return {}
end

local function getThreadIdentityCompat()
	if canonicalMethods.getthreadidentity then
		return canonicalMethods.getthreadidentity()
	end
end

local function setThreadIdentityCompat(identity)
	if canonicalMethods.setthreadidentity then
		return canonicalMethods.setthreadidentity(identity)
	end
end

local executorIdentity

local function withThreadIdentityCompat(identity, callback, ...)
	if not (canonicalMethods.getthreadidentity and canonicalMethods.setthreadidentity) then
		return callback(...)
	end

	local oldIdentity = getThreadIdentityCompat()

	if oldIdentity == nil then
		return callback(...)
	elseif oldIdentity == identity then
		return callback(...)
	end

	local arguments = pack(...)
	setThreadIdentityCompat(identity)

	local results = pack(pcall(function()
		return callback(unpackValues(arguments, 1, arguments.n))
	end))

	pcall(setThreadIdentityCompat, oldIdentity)

	if not results[1] then
		error(results[2], 0)
	end

	return unpackValues(results, 2, results.n)
end

local function withExecutorIdentityCompat(callback, ...)
	if executorIdentity == nil then
		return callback(...)
	end

	return withThreadIdentityCompat(executorIdentity, callback, ...)
end

local function getLuaClosuresCompat()
	local filterError
	if canonicalMethods.filtergc then
		local ran, closures = pcall(canonicalMethods.filtergc, "function", {
			IgnoreExecutor = true,
		}, false)

		if ran and type(closures) == "table" then
			if not canonicalMethods.islclosure then
				return closures
			end

			local filtered = {}

			for _, closure in pairs(closures) do
				if type(closure) == "function" and canonicalMethods.islclosure(closure) then
					filtered[#filtered + 1] = closure
				end
			end

			return filtered
		end
		filterError = ran and "filtergc did not return a table" or closures
	end

	local closures = {}
	if not canonicalMethods.getgc then
		error(filterError or "Closure enumeration is unavailable", 0)
	end
	local objects = canonicalMethods.getgc(false)
	assert(type(objects) == "table", "getgc did not return a table")

	for _, object in pairs(objects) do
		if
			type(object) == "function"
			and (not canonicalMethods.islclosure or canonicalMethods.islclosure(object))
			and (not canonicalMethods.isexecutorclosure or not canonicalMethods.isexecutorclosure(object))
		then
			closures[#closures + 1] = object
		end
	end

	return closures
end

local function getRunningScriptsCompat()
	local scanError
	if canonicalMethods.getrunningscripts then
		local ran, scripts = pcall(canonicalMethods.getrunningscripts)

		if ran and type(scripts) == "table" then
			return scripts
		end
		scanError = ran and "getrunningscripts did not return a table" or scripts
	end
	if not (canonicalMethods.filtergc or canonicalMethods.getgc) then
		error(scanError or "Running script enumeration is unavailable", 0)
	end

	local scripts = {}
	local seen = {}

	for _, closure in pairs(getLuaClosuresCompat()) do
		if type(getfenv) == "function" then
			local ran, closureEnvironment = pcall(getfenv, closure)
			local script = ran and type(closureEnvironment) == "table" and rawget(closureEnvironment, "script")

			if typeof(script) == "Instance" and not seen[script] then
				seen[script] = true
				scripts[#scripts + 1] = script
			end
		end
	end

	return scripts
end

local globalMethods = {}

for name, method in pairs(canonicalMethods) do
	if type(method) == "function" then
		globalMethods[name] = method
	end
end

globalMethods.getluaclosures = (globalMethods.filtergc or globalMethods.getgc) and getLuaClosuresCompat
globalMethods.getrunningscripts = (globalMethods.getrunningscripts or globalMethods.getluaclosures)
	and getRunningScriptsCompat
globalMethods.getconstants = globalMethods.getconstants and getConstantsCompat
globalMethods.getupvalues = globalMethods.getupvalues and getUpvaluesCompat
globalMethods.getconstant = (globalMethods.getconstant or globalMethods.getconstants) and getConstantCompat
globalMethods.getupvalue = globalMethods.getupvalue and getUpvalueCompat

if globalMethods.getthreadidentity and globalMethods.setthreadidentity then
	globalMethods.withthreadidentity = withThreadIdentityCompat
	globalMethods.withExecutorIdentity = withExecutorIdentityCompat
end

-- Keep legacy module names at this boundary without copying the API table twice.
local aliases = {
	checkCaller = "checkcaller",
	newCClosure = "newcclosure",
	hookFunction = "hookfunction",
	restoreFunction = "restorefunction",
	filterGc = "filtergc",
	getGc = "getgc",
	getFunctionHash = "getfunctionhash",
	getLuaClosures = "getluaclosures",
	getCallStack = "getcallstack",
	getInfo = "getinfo",
	getSenv = "getsenv",
	getMenv = "getmenv",
	getTenv = "gettenv",
	getContext = "getthreadidentity",
	getConnections = "getconnections",
	getScriptBytecode = "getscriptbytecode",
	getScriptClosure = "getscriptclosure",
	getScriptFromThread = "getscriptfromthread",
	getRunningScripts = "getrunningscripts",
	getScriptHash = "getscripthash",
	getScripts = "getscripts",
	getNamecallMethod = "getnamecallmethod",
	getCallingScript = "getcallingscript",
	getLoadedModules = "getloadedmodules",
	getConstants = "getconstants",
	getUpvalues = "getupvalues",
	getProtos = "getprotos",
	getStack = "getstack",
	getConstant = "getconstant",
	getUpvalue = "getupvalue",
	getProto = "getproto",
	getMetatable = "getrawmetatable",
	getHui = "gethui",
	setClipboard = "setclipboard",
	setConstant = "setconstant",
	setContext = "setthreadidentity",
	withThreadIdentity = "withthreadidentity",
	setUpvalue = "setupvalue",
	setStack = "setstack",
	setReadOnly = "setreadonly",
	isLClosure = "islclosure",
	isReadOnly = "isreadonly",
	isXClosure = "isexecutorclosure",
	hookMetaMethod = "hookmetamethod",
	readFile = "readfile",
	writeFile = "writefile",
	makeFolder = "makefolder",
	isFolder = "isfolder",
	isFile = "isfile",
	othHook = "oth_hook",
	othUnhook = "oth_unhook",
	othGetRootCallback = "oth_get_root_callback",
	othGetOriginalThread = "oth_get_original_thread",
	othIsHookThread = "oth_is_hook_thread",
	raknetAddSendHook = "raknet_add_send_hook",
	raknetRemoveSendHook = "raknet_remove_send_hook",
	raknetAddReceiveHook = "raknet_add_receive_hook",
	raknetRemoveReceiveHook = "raknet_remove_receive_hook",
	raknetSend = "raknet_send",
}

for alias, name in pairs(aliases) do
	globalMethods[alias] = globalMethods[name]
end

local MAX_SOURCE_BYTES = 1048576

local function httpGet(url, maximumBytes)
	maximumBytes = maximumBytes or MAX_SOURCE_BYTES
	local lastError
	local function accept(body)
		if type(body) ~= "string" or #body == 0 then
			return nil
		end
		assert(#body <= maximumBytes, "Hydroxide response exceeds the size limit: " .. url)
		return body
	end

	if globalMethods.request then
		local ran, response = pcall(globalMethods.request, { Url = url, Method = "GET" })
		if ran and type(response) == "table" then
			local status = response.StatusCode
			local success = type(status) == "number" and status >= 200 and status < 300
				or status == nil and response.Success == true
			if success then
				local body = accept(response.Body)
				if body then
					return body
				end
			end
			lastError = "HTTP " .. tostring(status or "unknown")
		else
			lastError = tostring(response)
		end
	end

	local fallbacks = {
		globalMethods.httpget or false,
		function() return game:HttpGet(url) end,
		function() return game:HttpGetAsync(url) end,
	}
	for _, getter in ipairs(fallbacks) do
		if getter then
			local ran, response = pcall(getter, url)
			if ran then
				local body = accept(response)
				if body then
					return body
				end
			else
				lastError = tostring(response)
			end
		end
	end
	error("Hydroxide could not download " .. url .. ": " .. tostring(lastError or "empty response"), 0)
end

local function resolveBranchVersion(targetUser, targetRepository, targetBranch)
	local url = ("https://api.github.com/repos/%s/%s/commits/%s"):format(
		targetUser,
		targetRepository,
		HttpService:UrlEncode(targetBranch)
	)
	local payload = HttpService:JSONDecode(httpGet(url))

	return payload and (payload.sha or (payload.commit and payload.commit.sha))
end

globalMethods.httpGet = httpGet
globalMethods.resolveBranchVersion = resolveBranchVersion

local function isCommit(value)
	return type(value) == "string" and #value == 40 and value:match("^%x+$") ~= nil
end

local function validateAsset(asset)
	assert(
		type(asset) == "string" and asset:match("^[%w_][%w_/-]*$")
			and not asset:find("//", 1, true) and asset:sub(-1) ~= "/",
		"Invalid Hydroxide module path"
	)
	return asset
end

local function cacheFilePath(asset, hasFolders, version)
	if hasFolders then
		return ("hydroxide/cache/%s/%s/%s/%s.lua"):format(user, repository, version, asset)
	end
	return ("hydroxide-%s-%s-%s-%s.lua"):format(user, repository, version, asset:gsub("/", "-"))
end

local function rawAssetUrl(targetUser, targetRepository, targetBranch, asset)
	return ("https://raw.githubusercontent.com/%s/%s/%s/%s.lua"):format(
		targetUser, targetRepository, targetBranch, validateAsset(asset)
	)
end

local function ensureCacheFolder(file)
	local folder = ""
	for component in file:gmatch("([^/]+)/") do
		folder = folder == "" and component or folder .. "/" .. component
		if not globalMethods.isFolder(folder) then
			globalMethods.makeFolder(folder)
		end
	end
end

local function restoreHookRecord(hook)
	if type(hook) ~= "table" or hook.Active == false then
		return true
	end

	local restored = false

	if hook.Kind == "oth" and hook.Target and globalMethods.othUnhook then
		restored = pcall(globalMethods.othUnhook, hook.Target)
	elseif
		hook.Kind == "metamethod"
		and hook.Object
		and hook.Method
		and hook.Original
		and globalMethods.hookMetaMethod
	then
		restored = pcall(globalMethods.hookMetaMethod, hook.Object, hook.Method, hook.Original)
	elseif (hook.Kind == "function" or hook.Kind == "metamethod") and hook.Target then
		if globalMethods.restoreFunction then
			restored = pcall(globalMethods.restoreFunction, hook.Target)
		end

		if not restored and hook.Original and globalMethods.hookFunction then
			restored = pcall(globalMethods.hookFunction, hook.Target, hook.Original)
		end
	elseif hook.Closure and hook.Original and globalMethods.hookFunction then
		restored = pcall(globalMethods.hookFunction, hook.Closure.Data, hook.Original)
	end

	if restored then
		hook.Active = false
	end

	return restored
end

globalMethods.restoreHook = restoreHookRecord

local function createFunctionSourceCacheBudget(maximumEntries, maximumBytes)
	local budget = {
		Bytes = 0,
		Entries = 0,
		Head = 1,
		MaximumBytes = maximumBytes,
		MaximumEntries = maximumEntries,
		Order = {},
		Tail = 0,
	}

	function budget:TrimOrder()
		while self.Head <= self.Tail do
			local token = self.Order[self.Head]

			if token and token.Active then
				break
			end

			self.Order[self.Head] = nil
			self.Head = self.Head + 1
		end

		if self.Head > self.Tail then
			self.Order = {}
			self.Head = 1
			self.Tail = 0
		elseif
			(self.Head > 128 and self.Head > self.Tail / 2)
			or (self.Tail > 128 and self.Tail > math.max(128, self.Entries * 2))
		then
			local compacted = {}

			for index = self.Head, self.Tail do
				local retained = self.Order[index]

				if retained and retained.Active then
					compacted[#compacted + 1] = retained
				end
			end

			self.Order = compacted
			self.Head = 1
			self.Tail = #compacted
		end
	end

	function budget:Release(token, evict)
		if type(token) ~= "table" or token.Active ~= true then
			return
		end

		token.Active = false
		self.Bytes = math.max(0, self.Bytes - (tonumber(token.Bytes) or 0))
		self.Entries = math.max(0, self.Entries - 1)
		local evictCallback = token.Evict
		token.Evict = nil

		if evict and type(evictCallback) == "function" then
			pcall(evictCallback)
		end

		self:TrimOrder()
	end

	function budget:Reserve(bytes, evict)
		bytes = math.max(0, math.floor(tonumber(bytes) or 0))

		if bytes > self.MaximumBytes then
			return nil
		end

		local token = {
			Active = true,
			Bytes = bytes,
			Evict = evict,
		}
		self.Tail = self.Tail + 1
		self.Order[self.Tail] = token
		self.Bytes = self.Bytes + bytes
		self.Entries = self.Entries + 1

		while self.Entries > self.MaximumEntries or self.Bytes > self.MaximumBytes do
			self:TrimOrder()
			local oldest = self.Order[self.Head]

			if oldest and oldest.Active then
				self:Release(oldest, true)
			else
				break
			end
		end

		self:TrimOrder()

		return token.Active and token or nil
	end

	function budget:Clear()
		while self.Entries > 0 do
			self:TrimOrder()
			local token = self.Order[self.Head]

			if not token then
				break
			end

			self:Release(token, true)
		end

		self.Order = {}
		self.Head = 1
		self.Tail = 0
		self.Bytes = 0
		self.Entries = 0
	end

	return budget
end

local function initialize()
	local executorName = "Unknown"
	local executorVersion = "Unknown"

	if globalMethods.identifyexecutor then
		local ran, name, version = pcall(globalMethods.identifyexecutor)

		if ran then
			executorName = name or executorName
			executorVersion = version or executorVersion
		end
	end

	if globalMethods.getthreadidentity then
		local ran, identity = pcall(globalMethods.getthreadidentity)

		if ran and type(identity) == "number" then
			executorIdentity = identity
		end
	end

	runtime = {
		Exited = false,
		Events = {},
		Hooks = {},
		Instances = {},
		DisabledConnections = {},
		Cache = importCache,
		Methods = globalMethods,
		Settings = runtimeSettings,
		FunctionSourceCache = createFunctionSourceCacheBudget(
			runtimeSettings.MaxFunctionSourceCacheEntries,
			runtimeSettings.MaxFunctionSourceCacheBytes
		),
		Runtime = {
			Name = executorName,
			Version = executorVersion,
			Identity = executorIdentity,
			Owner = user,
			Repository = repository,
			Branch = branch,
		},
		Constants = {
			Types = {
				["nil"] = "rbxassetid://4800232219",
				table = "rbxassetid://4666594276",
				string = "rbxassetid://4666593882",
				number = "rbxassetid://4666593882",
				boolean = "rbxassetid://4666593882",
				userdata = "rbxassetid://4666594723",
				vector = "rbxassetid://4666594723",
				buffer = "rbxassetid://4666593882",
				["function"] = "rbxassetid://4666593447",
				["thread"] = "rbxassetid://4666593447",
				["integral"] = "rbxassetid://4666593882",
			},
			Syntax = {
				["nil"] = Color3.fromRGB(244, 135, 113),
				table = Color3.fromRGB(225, 225, 225),
				string = Color3.fromRGB(225, 150, 85),
				number = Color3.fromRGB(170, 225, 127),
				boolean = Color3.fromRGB(127, 200, 255),
				userdata = Color3.fromRGB(225, 225, 225),
				vector = Color3.fromRGB(225, 225, 225),
				buffer = Color3.fromRGB(170, 225, 127),
				["function"] = Color3.fromRGB(225, 225, 225),
				["thread"] = Color3.fromRGB(225, 225, 225),
				["unnamed_function"] = Color3.fromRGB(175, 175, 175),
			},
		},
	}

	local exitRunning = false
	function runtime.Exit()
		if exitRunning then
			return false
		elseif runtime.ExitComplete then
			return true
		end
		exitRunning = true
		runtime.Exited = true
		local pendingEvents, pendingHooks, pendingConnections, pendingInstances = {}, {}, {}, {}
		for _, event in pairs(runtime.Events) do
			local ran, result = pcall(function()
				if event and event.Disconnect then
					return event:Disconnect()
				end
			end)
			if not ran or result == false then
				pendingEvents[#pendingEvents + 1] = event
			end
		end
		for _, hook in pairs(runtime.Hooks) do
			if not restoreHookRecord(hook) then
				pendingHooks[#pendingHooks + 1] = hook
			end
		end
		for _, connection in pairs(runtime.DisabledConnections) do
			local ran, result = pcall(function()
				if connection and connection.Enable then
					return connection:Enable()
				end
			end)
			if not ran or result == false then
				pendingConnections[#pendingConnections + 1] = connection
			end
		end
		runtime.Events, runtime.Hooks, runtime.DisabledConnections = pendingEvents, pendingHooks, pendingConnections

		local destroyed = {}
		local function destroy(instance)
			if typeof(instance) == "Instance" and not destroyed[instance] then
				destroyed[instance] = true
				local ran, result = pcall(function() return instance:Destroy() end)
				if not ran or result == false then
					pendingInstances[#pendingInstances + 1] = instance
				end
			end
		end
		for _, instance in pairs(runtime.Instances) do
			destroy(instance)
		end
		for asset, values in pairs(importCache) do
			if asset:match("^rbxassetid://%d+$") then
				destroy(values[1])
			end
			importCache[asset] = nil
		end
		for asset in pairs(sourceCache) do
			sourceCache[asset] = nil
		end
		runtime.Instances = pendingInstances
		runtime.FunctionSourceCache:Clear()
		runtime.ExitComplete = #pendingEvents == 0 and #pendingHooks == 0 and #pendingConnections == 0
			and #pendingInstances == 0
		if runtime.ExitComplete and environment.oh == runtime then
			for name, value in pairs(publishedGlobals) do
				if environment[name] == value then
					environment[name] = originalGlobals[name].Value
				end
			end
		end
		exitRunning = false
		return runtime.ExitComplete
	end

	useMethods({ oh = runtime, hasMethods = hasMethods })

	useMethods(globalMethods)
	useMethods({
		httpGet = httpGet,
		resolveBranchVersion = resolveBranchVersion,
	})

	if config.suppressScriptErrors == true and globalMethods.getConnections then
		local ran, connections = pcall(globalMethods.getConnections, game:GetService("ScriptContext").Error)

		if ran and type(connections) == "table" then
			for _, connection in pairs(connections) do
				if connection and connection.Disable and connection.Enabled ~= false then
					local disabled = pcall(function()
						connection:Disable()
					end)

					if disabled then
						runtime.DisabledConnections[#runtime.DisabledConnections + 1] = connection
					end
				end
			end
		end
	end

	local sourceRef = branch
	if web and not isCommit(sourceRef) then
		local ran, result = pcall(resolveBranchVersion, user, repository, branch)
		assert(ran and isCommit(result), "Could not resolve Hydroxide branch; retry or set branch to a full commit SHA")
		sourceRef = result
	end
	if isCommit(sourceRef) then
		sourceRef = sourceRef:lower()
		runtime.Runtime.Commit = sourceRef
	end

	local hasFolders = globalMethods.isFolder and globalMethods.makeFolder
	local usePersistentCache = false
	local sourceHashes
	if web and config.cache ~= false and hashContent and globalMethods.readFile and globalMethods.writeFile then
		-- Verify the documented hash format before trusting files from local storage.
		local hashed, digest = pcall(hashContent, "", "sha1")
		if hashed and type(digest) == "string" and digest:lower() == "da39a3ee5e6b4b0d3255bfef95601890afd80709" then
			local fetched, tree = pcall(function()
				local url = ("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1"):format(user, repository, sourceRef)
				return HttpService:JSONDecode(httpGet(url, MAX_SOURCE_BYTES * 4))
			end)
			if fetched and type(tree) == "table" and tree.truncated == false and type(tree.tree) == "table" then
				sourceHashes = {}
				for _, entry in ipairs(tree.tree) do
					if type(entry) == "table" and entry.type == "blob" and isCommit(entry.sha)
						and type(entry.path) == "string" and entry.path:sub(-4) == ".lua" then
						sourceHashes[entry.path:sub(1, -5)] = entry.sha:lower()
					end
				end
				usePersistentCache = true
			end
		end
	end
	runtime.Runtime.PersistentCache = usePersistentCache

	local function ensureActive()
		assert(not runtime.Exited and environment.oh == runtime, "Hydroxide session was closed")
	end

	local function runOnce(pendingLoads, asset, callback)
		ensureActive()
		local pending = pendingLoads[asset]
		if pending then
			assert(pending.Owner ~= coroutine.running(), "Circular Hydroxide import: " .. asset)
			while not pending.Results do
				assert(task and task.wait, "Concurrent Hydroxide imports require task.wait")
				task.wait()
				ensureActive()
			end
		else
			pending = { Owner = coroutine.running() }
			pendingLoads[asset] = pending
			pending.Results = pack(pcall(callback))
			pendingLoads[asset] = nil
		end
		local results = pending.Results
		if not results[1] then
			error(results[2], 0)
		end
		ensureActive()
		return unpackValues(results, 2, results.n)
	end

	local function validateSource(content, asset)
		assert(type(content) == "string" and #content > 0, "Empty Hydroxide source: " .. asset)
		assert(#content <= MAX_SOURCE_BYTES, "Hydroxide source exceeds the size limit: " .. asset)
		if sourceHashes then
			local expected = sourceHashes[asset]
			assert(expected, "Hydroxide module is missing from the resolved commit: " .. asset)
			local digest = hashContent("blob " .. #content .. "\0" .. content, "sha1")
			assert(type(digest) == "string" and digest:lower() == expected, "Hydroxide source checksum mismatch: " .. asset)
		end
		return content
	end

	local importAsset, prefetch
	local function executeSource(content, chunkName)
		-- Bind session locals without setfenv: a yielded module or callback must
		-- never resolve oh/import/prefetch from a replacement session's globals.
		local chunk, compileError = loadstring("return function(oh, import, prefetch, ...) " .. content .. "\nend", chunkName)
		assert(type(chunk) == "function", compileError or "Hydroxide source did not compile: " .. chunkName)
		ensureActive()
		return pack(chunk()(runtime, importAsset, prefetch))
	end

	local function loadWebSource(asset)
		validateAsset(asset)
		if sourceCache[asset] then
			return sourceCache[asset]
		end
		return runOnce(loadingSources, asset, function()
			local content
			local file = usePersistentCache and cacheFilePath(asset, hasFolders, sourceRef)
			if file then
				local read, cached = pcall(globalMethods.readFile, file)
				if read and pcall(validateSource, cached, asset) then
					content = cached
				end
			end
			if not content then
				content = validateSource(httpGet(rawAssetUrl(user, repository, sourceRef, asset)), asset)
				ensureActive()
				if file then
					pcall(function()
						if hasFolders then
							ensureCacheFolder(file)
						end
						globalMethods.writeFile(file, content)
					end)
				end
			end
			ensureActive()
			sourceCache[asset] = content
			return content
		end)
	end

	prefetch = function(assets)
		ensureActive()
		if not web or type(assets) ~= "table" then
			return true, {}
		end

		local queue = {}
		local seen = {}

		for _, asset in ipairs(assets) do
			if
				type(asset) == "string"
				and not asset:match("^rbxassetid://%d+$")
				and not importCache[asset]
				and not sourceCache[asset]
				and not seen[asset]
			then
				seen[asset] = true
				queue[#queue + 1] = asset
			end
		end

		if #queue == 0 then
			return true, {}
		end

		local errors = {}

		if not (task and task.spawn) then
			for _, asset in ipairs(queue) do
				local loaded, loadError = pcall(loadWebSource, asset)

				if not loaded then
					errors[#errors + 1] = ("%s: %s"):format(asset, tostring(loadError))
				end
			end

			return #errors == 0, errors
		end

		local nextIndex = 0
		local workerCount = math.min(runtimeSettings.MaxConcurrentImports, #queue)
		local remainingWorkers = workerCount

		for _ = 1, workerCount do
			task.spawn(function()
				while not runtime.Exited do
					nextIndex = nextIndex + 1

					local asset = queue[nextIndex]

					if not asset then
						break
					end

					local loaded, loadError = pcall(loadWebSource, asset)

					if not loaded then
						errors[#errors + 1] = ("%s: %s"):format(asset, tostring(loadError))
					end
				end

				remainingWorkers = remainingWorkers - 1
			end)
		end

		while remainingWorkers > 0 do
			ensureActive()
			task.wait()
		end

		return #errors == 0, errors
	end

	importAsset = function(asset)
		ensureActive()
		assert(type(asset) == "string", "Hydroxide imports require a module path or asset ID")
		local assetId = asset:match("^rbxassetid://%d+$")
		if not assetId then
			validateAsset(asset)
		end
		if importCache[asset] then
			local cached = importCache[asset]
			return unpackValues(cached, 1, cached.n)
		end
		return runOnce(loadingModules, asset, function()
			local assets
			if assetId then
				local objects = game:GetObjects(asset)
				assert(objects and objects[1], "Hydroxide could not load UI asset: " .. asset)
				if runtime.Exited or environment.oh ~= runtime then
					for _, object in pairs(objects) do
						runtime.Instances[#runtime.Instances + 1] = object
					end
					runtime.ExitComplete = false
					runtime.Exit()
					ensureActive()
				end
				assets = pack(objects[1])
			elseif web then
				assets = executeSource(loadWebSource(asset), asset .. ".lua")
				sourceCache[asset] = nil
			else
				assert(globalMethods.readFile, "Local imports require readfile")
				local content = globalMethods.readFile("hydroxide/" .. asset .. ".lua")
				assets = executeSource(validateSource(content, asset), asset .. ".lua")
			end
			ensureActive()
			importCache[asset] = assets
			return unpackValues(assets, 1, assets.n)
		end)
	end

	ensureActive()
	useMethods({
		import = importAsset,
		prefetch = prefetch,
		httpGet = httpGet,
		resolveBranchVersion = resolveBranchVersion,
	})

	useMethods(importAsset("methods/string"))
	useMethods(importAsset("methods/table"))
	useMethods(importAsset("methods/userdata"))
	useMethods(importAsset("methods/scriptbuilder"))
	useMethods(importAsset("methods/environment"))

	if config.autoLaunch ~= false then
		importAsset("ui/main")
	end
	return runtime
end

local initialized, result = pcall(initialize)
if not initialized then
	if runtime and runtime.Exit then
		pcall(runtime.Exit)
	end
	error("Hydroxide initialization failed: " .. tostring(result), 0)
end
return result
