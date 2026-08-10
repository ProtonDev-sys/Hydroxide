local environment = assert(getgenv, "<OH> ~ Your exploit is not supported")()
local previousRuntime = environment.oh

if previousRuntime and type(previousRuntime.Exit) == "function" then
    pcall(previousRuntime.Exit)
end

local HttpService = game:GetService("HttpService")

local config = type(environment.HydroxideConfig) == "table" and environment.HydroxideConfig or {}
local web = config.web ~= false
local user = config.owner or "ProtonDev-sys"
local repository = config.repository or "Hydroxide"
local branch = config.branch or "potassium-modernization-fork"
local importCache = {}
local pack = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack

local function numberSetting(name, defaultValue, minimum, maximum)
    local value = tonumber(config[name]) or defaultValue

    value = math.floor(value)
    return math.max(minimum, math.min(maximum, value))
end

local runtimeSettings = {
    CaptureExecutorCalls = config.captureExecutorCalls ~= false,
    CaptureCallStacks = config.captureCallStacks ~= false,
    MaxStackFrames = numberSetting("maxStackFrames", 24, 1, 64),
    MaxRemoteLogs = numberSetting("maxRemoteLogs", 500, 25, 5000),
    MaxClosureLogs = numberSetting("maxClosureLogs", 500, 25, 5000),
    MaxRenderedLogs = numberSetting("maxRenderedLogs", 100, 10, 500),
    MaxArgumentPreviewLength = numberSetting("maxArgumentPreviewLength", 240, 40, 2000),
    MaxHexBytes = numberSetting("maxHexBytes", 512, 32, 8192),
    MaxConcurrentImports = numberSetting("maxConcurrentImports", 6, 1, 12)
}

local function pick(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)

        if value ~= nil then
            return value
        end
    end
end

local function hasMethods(methods)
    for name in pairs(methods) do
        if not environment[name] then
            return false
        end
    end

    return true
end

local function useMethods(module)
    for name, method in pairs(module) do
        if method ~= nil then
            environment[name] = method
        end
    end
end

local function makeSetReadOnly()
    if setreadonly then
        return setreadonly
    elseif makereadonly and makewritable then
        return function(target, readonly)
            if readonly and makereadonly then
                return makereadonly(target)
            elseif not readonly and makewritable then
                return makewritable(target)
            end
        end
    elseif make_readonly and make_writeable then
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
    return pick(
        islclosure,
        is_l_closure,
        iscclosure and function(closure)
            return not iscclosure(closure)
        end
    )
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

local rawGetMetatable = pick(getrawmetatable, debug.getmetatable)
local othLibrary = pick(environment.oth, oth)
local httpLibrary = pick(environment.http, http)
local canonicalMethods = {
    checkcaller = pick(checkcaller, environment.checkcaller),
    newcclosure = pick(newcclosure, environment.newcclosure),
    hookfunction = pick(hookfunction, detour_function, environment.hookfunction),
    restorefunction = pick(restorefunction, environment.restorefunction),
    decompile = pick(decompile, environment.decompile),
    filtergc = pick(filtergc, environment.filtergc),
    getgc = pick(getgc, get_gc_objects, environment.getgc),
    getcallstack = pick(debug.getcallstack, getcallstack, environment.getcallstack),
    getinfo = pick(debug.getinfo, getinfo),
    getsenv = pick(getsenv, environment.getsenv),
    getmenv = pick(getsenv, getmenv),
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
    oth_is_hook_thread = othLibrary and othLibrary.is_hook_thread
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
    if canonicalMethods.filtergc then
        local ran, closures = pcall(canonicalMethods.filtergc, "function", {
            IgnoreExecutor = true
        }, false)

        if ran and type(closures) == "table" then
            if not canonicalMethods.islclosure then
                return closures
            end

            local filtered = {}

            for _, closure in pairs(closures) do
                if canonicalMethods.islclosure(closure) then
                    filtered[#filtered + 1] = closure
                end
            end

            return filtered
        end
    end

    local closures = {}
    local objects = canonicalMethods.getgc and canonicalMethods.getgc(false) or {}

    for _, object in pairs(objects) do
        if type(object) == "function"
            and (not canonicalMethods.islclosure or canonicalMethods.islclosure(object))
            and (not canonicalMethods.isexecutorclosure or not canonicalMethods.isexecutorclosure(object))
        then
            closures[#closures + 1] = object
        end
    end

    return closures
end

local function getRunningScriptsCompat()
    if canonicalMethods.getrunningscripts then
        local ran, scripts = pcall(canonicalMethods.getrunningscripts)

        if ran and type(scripts) == "table" then
            return scripts
        end
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

local globalMethods = {
    checkcaller = canonicalMethods.checkcaller,
    newcclosure = canonicalMethods.newcclosure,
    hookfunction = canonicalMethods.hookfunction,
    restorefunction = canonicalMethods.restorefunction,
    decompile = canonicalMethods.decompile,
    filtergc = canonicalMethods.filtergc,
    getgc = canonicalMethods.getgc,
    getluaclosures = getLuaClosuresCompat,
    getcallstack = canonicalMethods.getcallstack,
    getinfo = canonicalMethods.getinfo,
    getsenv = canonicalMethods.getsenv,
    getmenv = canonicalMethods.getmenv,
    gettenv = canonicalMethods.gettenv,
    getthreadidentity = canonicalMethods.getthreadidentity,
    getconnections = canonicalMethods.getconnections,
    getscriptbytecode = canonicalMethods.getscriptbytecode,
    getscriptclosure = canonicalMethods.getscriptclosure,
    getscriptfromthread = canonicalMethods.getscriptfromthread,
    getrunningscripts = getRunningScriptsCompat,
    getscripthash = canonicalMethods.getscripthash,
    getscripts = canonicalMethods.getscripts,
    getnamecallmethod = canonicalMethods.getnamecallmethod,
    getcallingscript = canonicalMethods.getcallingscript,
    getloadedmodules = canonicalMethods.getloadedmodules,
    getconstants = getConstantsCompat,
    getupvalues = getUpvaluesCompat,
    getprotos = canonicalMethods.getprotos,
    getstack = canonicalMethods.getstack,
    getconstant = getConstantCompat,
    getupvalue = getUpvalueCompat,
    getproto = canonicalMethods.getproto,
    getrawmetatable = canonicalMethods.getrawmetatable,
    gethui = canonicalMethods.gethui,
    setclipboard = canonicalMethods.setclipboard,
    setconstant = canonicalMethods.setconstant,
    setthreadidentity = canonicalMethods.setthreadidentity,
    withthreadidentity = canonicalMethods.getthreadidentity and canonicalMethods.setthreadidentity and withThreadIdentityCompat,
    withExecutorIdentity = canonicalMethods.getthreadidentity
        and canonicalMethods.setthreadidentity
        and withExecutorIdentityCompat,
    setupvalue = canonicalMethods.setupvalue,
    setstack = canonicalMethods.setstack,
    setreadonly = canonicalMethods.setreadonly,
    islclosure = canonicalMethods.islclosure,
    isreadonly = canonicalMethods.isreadonly,
    isexecutorclosure = canonicalMethods.isexecutorclosure,
    hookmetamethod = canonicalMethods.hookmetamethod,
    readfile = canonicalMethods.readfile,
    writefile = canonicalMethods.writefile,
    makefolder = canonicalMethods.makefolder,
    isfolder = canonicalMethods.isfolder,
    isfile = canonicalMethods.isfile,
    httpget = canonicalMethods.httpget,
    request = canonicalMethods.request,
    identifyexecutor = canonicalMethods.identifyexecutor,
    othHook = canonicalMethods.oth_hook,
    othUnhook = canonicalMethods.oth_unhook,
    othGetRootCallback = canonicalMethods.oth_get_root_callback,
    othGetOriginalThread = canonicalMethods.oth_get_original_thread,
    othIsHookThread = canonicalMethods.oth_is_hook_thread
}

globalMethods.checkCaller = globalMethods.checkcaller
globalMethods.newCClosure = globalMethods.newcclosure
globalMethods.hookFunction = globalMethods.hookfunction
globalMethods.restoreFunction = globalMethods.restorefunction
globalMethods.filterGc = globalMethods.filtergc
globalMethods.getGc = globalMethods.getgc
globalMethods.getLuaClosures = globalMethods.getluaclosures
globalMethods.getCallStack = globalMethods.getcallstack
globalMethods.getInfo = globalMethods.getinfo
globalMethods.getSenv = globalMethods.getsenv
globalMethods.getMenv = globalMethods.getmenv
globalMethods.getTenv = globalMethods.gettenv
globalMethods.getContext = globalMethods.getthreadidentity
globalMethods.getConnections = globalMethods.getconnections
globalMethods.getScriptBytecode = globalMethods.getscriptbytecode
globalMethods.getScriptClosure = globalMethods.getscriptclosure
globalMethods.getScriptFromThread = globalMethods.getscriptfromthread
globalMethods.getRunningScripts = globalMethods.getrunningscripts
globalMethods.getScriptHash = globalMethods.getscripthash
globalMethods.getScripts = globalMethods.getscripts
globalMethods.getNamecallMethod = globalMethods.getnamecallmethod
globalMethods.getCallingScript = globalMethods.getcallingscript
globalMethods.getLoadedModules = globalMethods.getloadedmodules
globalMethods.getConstants = globalMethods.getconstants
globalMethods.getUpvalues = globalMethods.getupvalues
globalMethods.getProtos = globalMethods.getprotos
globalMethods.getStack = globalMethods.getstack
globalMethods.getConstant = globalMethods.getconstant
globalMethods.getUpvalue = globalMethods.getupvalue
globalMethods.getProto = globalMethods.getproto
globalMethods.getMetatable = globalMethods.getrawmetatable
globalMethods.getHui = globalMethods.gethui
globalMethods.setClipboard = globalMethods.setclipboard
globalMethods.setConstant = globalMethods.setconstant
globalMethods.setContext = globalMethods.setthreadidentity
globalMethods.withThreadIdentity = globalMethods.withthreadidentity
globalMethods.setUpvalue = globalMethods.setupvalue
globalMethods.setStack = globalMethods.setstack
globalMethods.setReadOnly = globalMethods.setreadonly
globalMethods.isLClosure = globalMethods.islclosure
globalMethods.isReadOnly = globalMethods.isreadonly
globalMethods.isXClosure = globalMethods.isexecutorclosure
globalMethods.hookMetaMethod = globalMethods.hookmetamethod
globalMethods.readFile = globalMethods.readfile
globalMethods.writeFile = globalMethods.writefile
globalMethods.makeFolder = globalMethods.makefolder
globalMethods.isFolder = globalMethods.isfolder
globalMethods.isFile = globalMethods.isfile

local function httpGet(url)
    local requestFn = globalMethods.request

    if requestFn then
        local ran, response = pcall(requestFn, {
            Url = url,
            Method = "GET"
        })

        if ran
            and response
            and (response.Success or (response.StatusCode and response.StatusCode >= 200 and response.StatusCode < 300))
            and type(response.Body) == "string"
        then
            return response.Body
        end
    end

    if globalMethods.httpget then
        local ran, response = pcall(globalMethods.httpget, url)

        if ran and type(response) == "string" then
            return response
        end
    end

    local ran, response = pcall(function()
        return game:HttpGet(url)
    end)

    if ran and type(response) == "string" then
        return response
    end

    ran, response = pcall(function()
        return game:HttpGetAsync(url)
    end)

    if ran and type(response) == "string" then
        return response
    end

    error("Unable to GET remote content: " .. url)
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

local function cacheFilePath(asset, hasFolderFunctions, targetUser, version)
    if hasFolderFunctions then
        return ("hydroxide/cache/%s/%s/%s.lua"):format(targetUser, version, asset)
    end

    return ("hydroxide-%s-%s-%s.lua"):format(targetUser, version, asset:gsub("/", "-"))
end

local function rawAssetUrl(targetUser, targetRepository, targetBranch, asset)
    return ("https://raw.githubusercontent.com/%s/%s/%s/%s.lua"):format(
        targetUser,
        targetRepository,
        targetBranch,
        asset
    )
end

local function ensureCacheFolders(targetUser, version)
    if not (globalMethods.isFolder and globalMethods.makeFolder) then
        return
    end

    local function createFolder(path)
        if not globalMethods.isFolder(path) then
            globalMethods.makeFolder(path)
        end
    end

    createFolder("hydroxide")
    createFolder("hydroxide/cache")
    createFolder("hydroxide/cache/" .. targetUser)

    local versionRoot = "hydroxide/cache/" .. targetUser .. "/" .. version

    createFolder(versionRoot)
    createFolder(versionRoot .. "/methods")
    createFolder(versionRoot .. "/modules")
    createFolder(versionRoot .. "/objects")
    createFolder(versionRoot .. "/ui")
    createFolder(versionRoot .. "/ui/controls")
    createFolder(versionRoot .. "/ui/modules")
end

local function restoreHookRecord(hook)
    if type(hook) ~= "table" or hook.Active == false then
        return
    end

    local restored = false

    if hook.Kind == "oth" and hook.Target and globalMethods.othUnhook then
        restored = pcall(globalMethods.othUnhook, hook.Target)
    elseif hook.Kind == "metamethod" and hook.Object and hook.Method and hook.Original and globalMethods.hookMetaMethod then
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

environment.hasMethods = hasMethods
environment.oh = {
    Events = {},
    Hooks = {},
    Instances = {},
    DisabledConnections = {},
    Cache = importCache,
    Methods = globalMethods,
    Settings = runtimeSettings,
    Runtime = {
        Name = executorName,
        Version = executorVersion,
        Identity = executorIdentity,
        Owner = user,
        Repository = repository,
        Branch = branch
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
            ["integral"] = "rbxassetid://4666593882"
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
            ["unnamed_function"] = Color3.fromRGB(175, 175, 175)
        }
    },
    Exit = function()
        local runtime = environment.oh

        if not runtime then
            return
        end

        for _, event in pairs(runtime.Events) do
            if event and event.Disconnect then
                pcall(function()
                    event:Disconnect()
                end)
            end
        end

        for _, hook in pairs(runtime.Hooks) do
            restoreHookRecord(hook)
        end

        for _, connection in pairs(runtime.DisabledConnections) do
            if connection and connection.Enable then
                pcall(function()
                    connection:Enable()
                end)
            end
        end

        for _, instance in pairs(runtime.Instances) do
            if typeof(instance) == "Instance" then
                pcall(function()
                    instance:Destroy()
                end)
            end
        end

        local ui = importCache["rbxassetid://11389137937"]
        local assets = importCache["rbxassetid://5042114982"]

        if ui and ui[1] then
            pcall(function()
                ui[1]:Destroy()
            end)
        end

        if assets and assets[1] then
            pcall(function()
                assets[1]:Destroy()
            end)
        end

        environment.oh = nil
    end
}

useMethods(globalMethods)
useMethods({
    httpGet = httpGet,
    resolveBranchVersion = resolveBranchVersion
})

if config.suppressScriptErrors ~= false and globalMethods.getConnections then
    local ran, connections = pcall(globalMethods.getConnections, game:GetService("ScriptContext").Error)

    if ran and type(connections) == "table" then
        for _, connection in pairs(connections) do
            if connection and connection.Disable and connection.Enabled ~= false then
                local disabled = pcall(function()
                    connection:Disable()
                end)

                if disabled then
                    environment.oh.DisabledConnections[#environment.oh.DisabledConnections + 1] = connection
                end
            end
        end
    end
end

local currentVersion = branch
local versionResolved = branch:match("^%x+$") ~= nil and #branch == 40

if web and not versionResolved then
    local ran, result = pcall(resolveBranchVersion, user, repository, branch)

    if ran and result then
        currentVersion = result
        versionResolved = true
    end
end

local cacheVersion = currentVersion:gsub("[^%w_-]", "_")
local sourceRef = versionResolved and currentVersion or branch
environment.oh.Runtime.Commit = versionResolved and currentVersion or nil

local hasFileIO = globalMethods.readFile and globalMethods.writeFile
local hasFolderFunctions = globalMethods.isFolder and globalMethods.makeFolder
local usePersistentCache = web and hasFileIO and config.cache ~= false and versionResolved

if usePersistentCache then
    local cacheReady = pcall(ensureCacheFolders, user, cacheVersion)
    usePersistentCache = cacheReady
end

local function executeSource(content, chunkName)
    local chunk, compileError = loadstring(content, chunkName)

    assert(chunk, compileError)
    return pack(chunk())
end

local sourceCache = {}

local function loadWebSource(asset)
    if sourceCache[asset] then
        return sourceCache[asset]
    end

    local content

    if usePersistentCache then
        local file = cacheFilePath(asset, hasFolderFunctions, user, cacheVersion)
        local canReadCache = true

        if globalMethods.isFile then
            local checked, exists = pcall(globalMethods.isFile, file)
            canReadCache = checked and exists
        end

        if canReadCache then
            local ran, result = pcall(globalMethods.readFile, file)

            if ran and type(result) == "string" then
                content = result
            end
        end

        if not content then
            content = httpGet(rawAssetUrl(user, repository, sourceRef, asset))
            pcall(globalMethods.writeFile, file, content)
        end
    else
        content = httpGet(rawAssetUrl(user, repository, sourceRef, asset))
    end

    sourceCache[asset] = content
    return content
end

local function prefetch(assets)
    if not web or type(assets) ~= "table" then
        return true, {}
    end

    local queue = {}
    local seen = {}

    for _, asset in ipairs(assets) do
        if type(asset) == "string"
            and not asset:find("rbxassetid://", 1, true)
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
            while true do
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
        task.wait()
    end

    return #errors == 0, errors
end

function environment.import(asset)
    if importCache[asset] then
        local cached = importCache[asset]
        return unpackValues(cached, 1, cached.n or #cached)
    end

    local assets

    if asset:find("rbxassetid://", 1, true) then
        assets = pack(game:GetObjects(asset)[1])
    elseif web then
        local content = loadWebSource(asset)
        assets = executeSource(content, asset .. ".lua")
        sourceCache[asset] = nil
    else
        assert(globalMethods.readFile, "Local imports require readfile")
        assets = executeSource(globalMethods.readFile("hydroxide/" .. asset .. ".lua"), asset .. ".lua")
    end

    importCache[asset] = assets
    return unpackValues(assets, 1, assets.n or #assets)
end

useMethods({
    import = environment.import,
    prefetch = prefetch,
    httpGet = httpGet,
    resolveBranchVersion = resolveBranchVersion
})

useMethods(import("methods/string"))
useMethods(import("methods/table"))
useMethods(import("methods/userdata"))
useMethods(import("methods/environment"))

--import("ui/main")
