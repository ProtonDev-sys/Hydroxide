-- Exercise the real initializer and importer with isolated executor/Roblox boundaries.
local function equal(actual, expected, label)
	assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function fails(callback, text)
	local ok, err = pcall(callback)
	assert(not ok and tostring(err):find(text, 1, true), "expected failure containing " .. text .. ", got " .. tostring(err))
end
local COMMIT = string.rep("a", 40)
local EMPTY = "return {}"
local EMPTY_HASH = "3941af59e075e935ce0701e491d7796f6c9a51d9"
local UI = 'uiStarts = (uiStarts or 0) + 1; return import("rbxassetid://11389137937")'
local UI_HASH = "5d164f228f287322dbc3f2a9c743cc43ccd78845"
local CORE = { "methods/string", "methods/table", "methods/userdata", "methods/scriptbuilder", "methods/environment" }
local function fixture(config)
	local state = { sources = {}, requests = {}, files = {}, reads = 0, writes = 0, destroyed = 0, compiled = {} }
	for _, asset in ipairs(CORE) do state.sources[asset] = EMPTY end
	state.sources["ui/main"] = UI
	local env = setmetatable({ HydroxideConfig = config or {}, debug = {} }, { __index = _G })
	env._G = env
	env.getgenv = function() return env end
	env.typeof = function(value) return type(value) == "table" and value.IsInstance and "Instance" or type(value) end
	env.Color3 = { fromRGB = function(...) return { ... } end }
	env.loadstring = function(source, name)
		state.compiled[#state.compiled + 1] = name
		return load(source, "@" .. name, "t", env)
	end
	env.readfile = function(file)
		state.reads = state.reads + 1
		local asset = file:match("^hydroxide/(.+)%.lua$")
		if env.HydroxideConfig.web == false and asset then return assert(state.sources[asset], "missing local source") end
		return assert(state.files[file], "missing cache")
	end
	env.writefile = function(file, source)
		state.writes = state.writes + 1
		state.files[file] = source
	end
	env.isfolder = function() return true end
	env.makefolder = function() end
	env.game = {}
	function env.game:GetService(name)
		if name == "HttpService" then
			return {
				UrlEncode = function(_, value)
					return value:gsub("([^%w_.~-])", function(c) return ("%%%02X"):format(c:byte()) end)
				end,
				JSONDecode = function(_, body)
					if body == "commit" then return { sha = state.commit or COMMIT } end
					if body == "tree" then
						local entries = {}
						for asset in pairs(state.sources) do
							entries[#entries + 1] = { type = "blob", path = asset .. ".lua", sha = asset == "ui/main" and UI_HASH or EMPTY_HASH }
						end
						return { truncated = false, tree = entries }
					end
					error("invalid JSON")
				end,
			}
		elseif name == "ScriptContext" then return { Error = {} } end
		error("unexpected service " .. name)
	end
	function env.game:GetObjects()
		return { { IsInstance = true, Destroy = function() state.destroyed = state.destroyed + 1 end } }
	end
	function env.game:HttpGet() error("HttpGet unavailable") end
	function env.game:HttpGetAsync() error("HttpGetAsync unavailable") end
	state.respond = function(url)
		if url:find("/commits/", 1, true) then return "commit" end
		if url:find("/git/trees/", 1, true) then return "tree" end
		local asset = url:match("/" .. COMMIT .. "/(.+)%.lua$")
		return assert(asset and state.sources[asset], "unexpected URL " .. url)
	end
	env.request = function(options)
		equal(options.Method, "GET", "documented request method")
		state.requests[#state.requests + 1] = options.Url
		return { StatusCode = 200, Success = true, Body = state.respond(options.Url) }
	end
	function state.enableHash()
		env.crypt = { hash = function(data, algorithm)
			equal(algorithm, "sha1", "Git blob hash algorithm")
			if data == "" then return "da39a3ee5e6b4b0d3255bfef95601890afd80709" end
			if data == "blob " .. #EMPTY .. "\0" .. EMPTY then return EMPTY_HASH end
			if data == "blob " .. #UI .. "\0" .. UI then return UI_HASH end
			return string.rep("b", 40)
		end }
	end
	function state.start() return assert(loadfile("init.lua", "t", env))() end
	return state, env
end

do
	local state, env = fixture()
	local original = function() return "original" end
	env.getconstants, env.import = original, original
	env.getconnections = function() error("default startup must not suppress other error listeners") end
	local runtime = state.start()
	equal(runtime.Runtime.Branch, "main", "default branch")
	equal(runtime.Runtime.Commit, COMMIT, "resolved commit")
	equal(runtime.Settings.MaxRakNetLogs, 500, "bounded packet history default")
	equal(runtime.Settings.MaxRakNetHistoryBytes, 16777216, "bounded packet bytes default")
	equal(env.uiStarts, 1, "initializer opens UI")
	env.import("ui/main")
	equal(env.uiStarts, 1, "legacy explicit UI import remains idempotent")
	equal(runtime.Runtime.PersistentCache, false, "disk cache requires verified hashes")
	equal(state.reads, 0, "unverified disk files are not read")
	equal(env.hasMethods({ getconstants = true }), true, "callable capability")
	env.notAFunction = true
	equal(env.hasMethods({ notAFunction = true }), false, "non-callable capability rejected")
	local oldImport = env.import
	equal(runtime.Exit(), true, "cleanup succeeds")
	equal(env.getconstants, original, "canonical executor API restored")
	equal(env.import, original, "preexisting helper restored")
	equal(env.oh, nil, "runtime namespace removed")
	equal(state.destroyed, 1, "UI asset destroyed exactly once")
	equal(runtime.Exit(), true, "cleanup is idempotent")
	fails(function() oldImport("methods/string") end, "session was closed")
end

do
	local state, env = fixture({ autoLaunch = false, maxRemoteLogs = 0 / 0, maxStackFrames = math.huge })
	local runtime = state.start()
	equal(runtime.Settings.MaxRemoteLogs, 500, "NaN setting uses default")
	equal(runtime.Settings.MaxStackFrames, 24, "infinite setting uses default")
	equal(env.uiStarts, nil, "programmatic startup is optional")
	state.sources["modules/Tuple"] = 'return nil, false, "tail", nil'
	state.sources["modules/Varargs"] = 'return select("#", ...)'
	equal(env.import("modules/Varargs"), 0, "imported chunks preserve top-level varargs")
	for _ = 1, 2 do
		local tuple = table.pack(env.import("modules/Tuple"))
		equal(tuple.n, 4, "cached tuple arity")
		equal(tuple[2], false, "cached false result")
		equal(tuple[3], "tail", "cached non-nil result")
	end
	for _, asset in ipairs({ "../secret", "/absolute", "modules//Remote", "modules/Remote.lua", "rbxassetid://1/../../secret" }) do
		fails(function() env.import(asset) end, "Invalid Hydroxide module path")
	end
	local replacement = function() end
	env.getInfo = replacement
	runtime.Exit()
	equal(env.getInfo, replacement, "later third-party globals are preserved")
end

do
	local state, env = fixture({ autoLaunch = false })
	env.getrunningscripts = function() error("native scan unavailable") end
	local runtime = state.start()
	fails(env.getRunningScripts, "native scan unavailable")
	runtime.Exit()
	env.filtergc = function() error("native filter unavailable") end
	runtime = state.start()
	fails(env.getLuaClosures, "native filter unavailable")
	runtime.Exit()
	local closure, script = function() end, { IsInstance = true }
	env.getgc = function() return { false, {}, closure } end
	env.getfenv = function() return { script = script } end
	runtime = state.start()
	equal(env.getLuaClosures()[1], closure, "failed native filter falls back to GC")
	equal(env.getRunningScripts()[1], script, "failed native scan falls back to GC")
	runtime.Exit()
end

do
	local state, env = fixture({ autoLaunch = false })
	local identity = 2
	env.getthreadidentity = function() return identity end
	env.setthreadidentity = function(value) identity = value end
	local runtime = state.start()
	local values = table.pack(env.withThreadIdentity(8, function() equal(identity, 8); return nil, false end))
	equal(values.n, 2, "identity wrapper preserves return arity")
	equal(values[2], false, "identity wrapper preserves false")
	equal(identity, 2, "identity restored after success")
	fails(function() env.withThreadIdentity(8, function() error("inspection failed") end) end, "inspection failed")
	equal(identity, 2, "identity restored after failure")
	runtime.Exit()
end

do
	local state, env = fixture({ autoLaunch = false })
	local first = state.start()
	local second = state.start()
	equal(first.Exited, true, "repeat execution closes previous session")
	first.Exit()
	equal(env.oh, second, "stale Exit cannot close new session")
	env.HydroxideConfig.owner = "../invalid"
	fails(state.start, "Invalid Hydroxide repository owner")
	equal(second.Exited, false, "invalid configuration leaves active session intact")
	second.Exit()
end

do
	local state, env = fixture({ autoLaunch = false, branch = "feature/cleanup" })
	state.start()
	assert(state.requests[1]:find("feature%2Fcleanup", 1, true), "branch is URL encoded")
	for index = 2, #state.requests do assert(state.requests[index]:find(COMMIT, 1, true), "imports use one resolved commit") end
	env.oh.Exit()
	state.commit = "not-a-commit"
	fails(state.start, "Could not resolve Hydroxide branch")
	equal(env.oh, nil, "resolution failure cleans partial state")
end

do
	local state, env = fixture({ autoLaunch = false, branch = COMMIT })
	local rawRequest = env.request
	env.request = function(options)
		if options.Url:find("methods/string.lua", 1, true) then
			return { Success = true, StatusCode = 500, Body = "this must not execute" }
		end
		return rawRequest(options)
	end
	env.httpget = function() return EMPTY end
	state.start()
	equal(state.compiled[1], "methods/string.lua", "HTTP error falls back before compilation")
	env.oh.Exit()
	env.httpget = nil
	state.sources["methods/string"] = string.rep("x", 1048577)
	env.request = rawRequest
	fails(state.start, "response exceeds the size limit")
	equal(env.oh, nil, "oversized startup cleans globals")
end

do
	local state, env = fixture({ autoLaunch = false })
	state.enableHash()
	local path = "hydroxide/cache/ProtonDev-sys/Hydroxide/" .. COMMIT .. "/methods/string.lua"
	state.files[path] = "untrustedCacheExecuted = true; return {}"
	local runtime = state.start()
	equal(runtime.Runtime.PersistentCache, true, "verified cache enabled")
	equal(env.untrustedCacheExecuted, nil, "corrupt cache never executes")
	equal(state.files[path], EMPTY, "corrupt cache repaired from pinned source")
	equal(state.writes, #CORE, "validated modules cached once")
	runtime.Exit()
	state.requests = {}
	state.start()
	equal(#state.requests, 2, "warm startup only resolves commit and trusted tree")
	env.oh.Exit()
	state.sources["methods/string"] = "untrustedDownloadExecuted = true; return {}"
	state.files[path] = nil
	fails(state.start, "source checksum mismatch")
	equal(env.untrustedDownloadExecuted, nil, "mismatched download never executes")
	equal(env.oh, nil, "checksum failure cleans globals")
end

do
	local state, env = fixture({ autoLaunch = false })
	state.enableHash()
	local respond = state.respond
	state.respond = function(url)
		if url:find("/git/trees/", 1, true) then error("tree unavailable") end
		return respond(url)
	end
	local runtime = state.start()
	equal(runtime.Runtime.PersistentCache, false, "missing trusted tree bypasses disk cache")
	equal(state.reads, 0, "unverified cache is never read")
	runtime.Exit()
end

do
	local state, env = fixture({ web = false, autoLaunch = false })
	state.sources["methods/string"] = "invalid lua !!"
	fails(state.start, "initialization failed")
	equal(env.oh, nil, "compile failure rolls back globals")
	state.sources["methods/string"] = EMPTY
	state.sources["ui/main"] = 'import("rbxassetid://11389137937"); error("UI setup failed")'
	env.HydroxideConfig.autoLaunch = true
	fails(state.start, "UI setup failed")
	equal(state.destroyed, 1, "partially initialized UI is destroyed")
	equal(env.oh, nil, "UI failure rolls back globals")
end

do
	local state, env = fixture({ autoLaunch = false })
	state.start()
	env.task = { wait = function() coroutine.yield("wait") end }
	state.sources["modules/Yield"] = 'executions = (executions or 0) + 1; task.wait(); return nil, false, 7'
	local tuples = {}
	local function importer(index)
		return coroutine.create(function() tuples[index] = table.pack(env.import("modules/Yield")) end)
	end
	local first, second = importer(1), importer(2)
	assert(coroutine.resume(first))
	assert(coroutine.resume(second))
	assert(coroutine.resume(first))
	assert(coroutine.resume(second))
	equal(env.executions, 1, "concurrent imports execute once")
	equal(tuples[1].n, 3, "first importer tuple arity")
	equal(tuples[2][2], false, "waiting importer gets false result")
	state.sources["modules/Cycle"] = 'return import("modules/Cycle")'
	fails(function() env.import("modules/Cycle") end, "Circular Hydroxide import")
	local respond = state.respond
	state.sources["modules/Late"] = "lateExecuted = true; return {}"
	state.respond = function(url)
		if url:find("modules/Late.lua", 1, true) then coroutine.yield("download") end
		return respond(url)
	end
	local late = coroutine.create(function() env.import("modules/Late") end)
	assert(coroutine.resume(late))
	env.oh.Exit()
	local resumed, err = coroutine.resume(late)
	assert(not resumed and tostring(err):find("session was closed", 1, true), "late import is cancelled")
	equal(env.lateExecuted, nil, "closed session never executes a late download")
end

do
	local state, env = fixture({ autoLaunch = false })
	local old = state.start()
	env.task = { wait = function() coroutine.yield("wait") end }
	state.sources["modules/Paused"] = 'task.wait(); oh.WrittenByClosedModule = true; return {}'
	local paused = coroutine.create(function() env.import("modules/Paused") end)
	assert(coroutine.resume(paused))
	local replacement = state.start()
	local resumed, err = coroutine.resume(paused)
	assert(not resumed and tostring(err):find("session was closed", 1, true), "closed in-flight module is rejected")
	equal(old.WrittenByClosedModule, true, "module captures its original runtime")
	equal(replacement.WrittenByClosedModule, nil, "closed module cannot write into new runtime")
	replacement.Exit()
end

for _, endpoint in ipairs({ "/commits/", "/git/trees/" }) do
	local state, env = fixture({ autoLaunch = false })
	state.enableHash()
	local respond, paused = state.respond, false
	state.respond = function(url)
		if not paused and url:find(endpoint, 1, true) then
			paused = true
			coroutine.yield("startup download")
		end
		return respond(url)
	end
	local first = coroutine.create(state.start)
	assert(coroutine.resume(first))
	equal(coroutine.status(first), "suspended", "first startup pauses during " .. endpoint)
	local replacement = state.start()
	local replacementImport, replacementPrefetch = env.import, env.prefetch
	local resumed, err = coroutine.resume(first)
	assert(not resumed and tostring(err):find("session was closed", 1, true), "superseded startup is rejected")
	equal(env.oh, replacement, "superseded startup preserves active runtime")
	equal(env.import, replacementImport, "superseded startup preserves active importer")
	equal(env.prefetch, replacementPrefetch, "superseded startup preserves active prefetch")
	assert(type(env.import("methods/string")) == "table", "active importer remains usable")
	replacement.Exit()
end

do
	local state, env = fixture({ autoLaunch = false })
	local runtime = state.start()
	local attempts = 0
	runtime.Instances[1] = { IsInstance = true, Destroy = function()
		attempts = attempts + 1
		if attempts == 1 then error("temporary destruction failure") end
	end }
	equal(runtime.Exit(), false, "failed instance cleanup remains retryable")
	equal(runtime.Exit(), true, "instance cleanup retry succeeds")
	equal(attempts, 2, "failed destruction is retried")
	state.start()
	local getObjects = env.game.GetObjects
	function env.game:GetObjects()
		coroutine.yield("asset download")
		return getObjects(self)
	end
	local late = coroutine.create(function() env.import("rbxassetid://123") end)
	assert(coroutine.resume(late))
	env.oh.Exit()
	local resumed = coroutine.resume(late)
	equal(resumed, false, "cancelled asset import is rejected")
	equal(state.destroyed, 1, "asset received after exit is destroyed")
end

do
	local state, env = fixture({ autoLaunch = false })
	local nativeInfo = function() return {} end
	env.debug.getinfo = nativeInfo
	local old = state.start()
	local getObjects = env.game.GetObjects
	function env.game:GetObjects()
		coroutine.yield("asset download")
		return getObjects(self)
	end
	local late = coroutine.create(function() env.import("rbxassetid://123") end)
	assert(coroutine.resume(late))
	old.Exit()
	local replacement = state.start()
	equal(env.getInfo, nativeInfo, "new session publishes shared native API")
	equal(coroutine.resume(late), false, "old asset import remains cancelled")
	equal(state.destroyed, 1, "old asset cleaned after replacement launch")
	equal(env.getInfo, nativeInfo, "late old cleanup cannot remove new native aliases")
	equal(env.oh, replacement, "late old cleanup preserves replacement ownership")
	replacement.Exit()
end

do
	local state, env = fixture({ autoLaunch = false, suppressScriptErrors = true })
	local enabled, restores = 0, 0
	env.getconnections = function()
		return { { Enabled = true, Disable = function() enabled = enabled - 1 end, Enable = function() enabled = enabled + 1 end } }
	end
	env.restorefunction = function()
		restores = restores + 1
		if restores == 1 then error("temporary restoration failure") end
	end
	local runtime = state.start()
	equal(enabled, -1, "legacy suppression requires explicit opt-in")
	runtime.Hooks[1] = { Kind = "function", Target = function() end }
	equal(runtime.Exit(), false, "failed hook cleanup remains retryable")
	equal(enabled, 0, "disabled listener restored")
	equal(env.oh, runtime, "unfinished cleanup retains its owner")
	equal(runtime.Exit(), true, "cleanup retry succeeds")
	equal(restores, 2, "failed hook restoration retried")
	equal(enabled, 0, "restored listener is not enabled twice")
	equal(env.oh, nil, "completed cleanup releases owner")
end
print("compat_spec.lua: real initializer, imports, cache integrity, lifecycle, and API boundaries ok")
