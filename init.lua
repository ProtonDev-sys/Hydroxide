local environment = assert(getgenv, "<OH> ~ Your exploit is not supported")()

if oh then
    oh.Exit()
end

local HttpService = game:GetService("HttpService")

local web = true
local user = "ProtonDev-sys"
local branch = "revision"
local importCache = {}

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
    return pick(
        setreadonly,
        function(target, readonly)
            if readonly and makereadonly then
                return makereadonly(target)
            elseif not readonly and makewritable then
                return makewritable(target)
            end
        end,
        function(target, readonly)
            if readonly and make_readonly then
                return make_readonly(target)
            elseif not readonly and make_writeable then
                return make_writeable(target)
            end
        end
    )
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
local canonicalMethods = {
    checkcaller = pick(checkcaller, environment.checkcaller),
    newcclosure = pick(newcclosure, environment.newcclosure),
    hookfunction = pick(hookfunction, detour_function, environment.hookfunction),
    getgc = pick(getgc, get_gc_objects, environment.getgc),
    getinfo = pick(debug.getinfo, getinfo),
    getsenv = pick(getsenv, environment.getsenv),
    getmenv = pick(getmenv, getsenv),
    getthreadcontext = pick(getthreadcontext, get_thread_context, syn and syn.get_thread_identity),
    getconnections = pick(getconnections, get_signal_cons),
    getscriptclosure = pick(getscriptclosure, get_script_function),
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
    setthreadcontext = pick(setthreadcontext, set_thread_context, syn and syn.set_thread_identity),
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
    request = pick(request, http_request, syn and syn.request),
    oth_hook = environment.oth and environment.oth.hook or (oth and oth.hook),
    oth_unhook = environment.oth and environment.oth.unhook or (oth and oth.unhook),
    oth_get_root_callback = environment.oth and environment.oth.get_root_callback or (oth and oth.get_root_callback)
}

canonicalMethods.hookmetamethod = makeHookMetaMethod(canonicalMethods.getrawmetatable)

if Window and PROTOSMASHER_LOADED then
    getgenv().get_script_function = nil
end

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

local function getThreadContextCompat(...)
    if canonicalMethods.getthreadcontext then
        return canonicalMethods.getthreadcontext(...)
    end
end

local function setThreadContextCompat(...)
    if canonicalMethods.setthreadcontext then
        return canonicalMethods.setthreadcontext(...)
    end
end

local globalMethods = {
    checkcaller = canonicalMethods.checkcaller,
    newcclosure = canonicalMethods.newcclosure,
    hookfunction = canonicalMethods.hookfunction,
    getgc = canonicalMethods.getgc,
    getinfo = canonicalMethods.getinfo,
    getsenv = canonicalMethods.getsenv,
    getmenv = canonicalMethods.getmenv,
    getthreadcontext = getThreadContextCompat,
    getconnections = canonicalMethods.getconnections,
    getscriptclosure = canonicalMethods.getscriptclosure,
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
    setthreadcontext = setThreadContextCompat,
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
    request = canonicalMethods.request,
    othHook = canonicalMethods.oth_hook,
    othUnhook = canonicalMethods.oth_unhook,
    othGetRootCallback = canonicalMethods.oth_get_root_callback
}

globalMethods.checkCaller = globalMethods.checkcaller
globalMethods.newCClosure = globalMethods.newcclosure
globalMethods.hookFunction = globalMethods.hookfunction
globalMethods.getGc = globalMethods.getgc
globalMethods.getInfo = globalMethods.getinfo
globalMethods.getSenv = globalMethods.getsenv
globalMethods.getMenv = globalMethods.getmenv
globalMethods.getContext = globalMethods.getthreadcontext
globalMethods.getConnections = globalMethods.getconnections
globalMethods.getScriptClosure = globalMethods.getscriptclosure
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
globalMethods.setContext = globalMethods.setthreadcontext
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

        if ran and response and response.Success and type(response.Body) == "string" then
            return response.Body
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

local function resolveBranchVersion(targetUser, targetBranch)
    local url = ("https://api.github.com/repos/%s/Hydroxide/branches/%s"):format(targetUser, targetBranch)
    local payload = HttpService:JSONDecode(httpGet(url))
    local commit = payload and payload.commit

    return commit and commit.sha
end

globalMethods.httpGet = httpGet
globalMethods.resolveBranchVersion = resolveBranchVersion

local function cacheFilePath(asset, hasFolderFunctions, targetUser)
    if hasFolderFunctions then
        return ("hydroxide/user/%s/%s.lua"):format(targetUser, asset)
    end

    return ("hydroxide-%s-%s.lua"):format(targetUser, asset:gsub("/", "-"))
end

local function rawAssetUrl(targetUser, targetBranch, asset)
    return ("https://raw.githubusercontent.com/%s/Hydroxide/%s/%s.lua"):format(targetUser, targetBranch, asset)
end

local function ensureCacheFolders(targetUser)
    if not (globalMethods.isFolder and globalMethods.makeFolder) then
        return
    end

    local function createFolder(path)
        if not globalMethods.isFolder(path) then
            globalMethods.makeFolder(path)
        end
    end

    createFolder("hydroxide")
    createFolder("hydroxide/user")
    createFolder("hydroxide/user/" .. targetUser)
    createFolder("hydroxide/user/" .. targetUser .. "/methods")
    createFolder("hydroxide/user/" .. targetUser .. "/modules")
    createFolder("hydroxide/user/" .. targetUser .. "/objects")
    createFolder("hydroxide/user/" .. targetUser .. "/ui")
    createFolder("hydroxide/user/" .. targetUser .. "/ui/controls")
    createFolder("hydroxide/user/" .. targetUser .. "/ui/modules")
end

environment.hasMethods = hasMethods
environment.oh = {
    Events = {},
    Hooks = {},
    Cache = importCache,
    Methods = globalMethods,
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
        for _, event in pairs(oh.Events) do
            if event and event.Disconnect then
                event:Disconnect()
            end
        end

        for original, hook in pairs(oh.Hooks) do
            local hookType = type(hook)

            if hookType == "function" and globalMethods.hookFunction then
                pcall(globalMethods.hookFunction, hook, original)
            elseif hookType == "table" then
                if hook.Kind == "function" and globalMethods.hookFunction then
                    pcall(globalMethods.hookFunction, hook.Target, hook.Original)
                elseif hook.Kind == "oth" and globalMethods.othUnhook and hook.Handle then
                    pcall(globalMethods.othUnhook, hook.Handle)
                elseif hook.Closure and hook.Original and globalMethods.hookFunction then
                    pcall(globalMethods.hookFunction, hook.Closure.Data, hook.Original)
                end
            end
        end

        local ui = importCache["rbxassetid://11389137937"]
        local assets = importCache["rbxassetid://5042114982"]

        if ui then
            unpack(ui):Destroy()
        end

        if assets then
            unpack(assets):Destroy()
        end
    end
}

useMethods(globalMethods)
useMethods({
    httpGet = httpGet,
    resolveBranchVersion = resolveBranchVersion
})

if globalMethods.getConnections then
    local setReadOnly = globalMethods.setReadOnly

    for _, connection in pairs(globalMethods.getConnections(game:GetService("ScriptContext").Error)) do
        local connectionMetatable = globalMethods.getMetatable and globalMethods.getMetatable(connection)
        local oldIndex = connectionMetatable and connectionMetatable.__index

        if not connectionMetatable then
            continue
        end

        if PROTOSMASHER_LOADED ~= nil then
            setwriteable(connectionMetatable)
        elseif setReadOnly then
            setReadOnly(connectionMetatable, false)
        end

        if oldIndex and globalMethods.newCClosure then
            connectionMetatable.__index = globalMethods.newCClosure(function(target, key)
                if key == "Connected" then
                    return true
                end

                return oldIndex(target, key)
            end)
        end

        if PROTOSMASHER_LOADED ~= nil then
            if setReadOnly then
                setReadOnly(connectionMetatable)
            end

            connection:Disconnect()
        else
            if setReadOnly then
                setReadOnly(connectionMetatable, true)
            end

            connection:Disable()
        end
    end
end

local currentVersion = branch

if web then
    local ran, result = pcall(resolveBranchVersion, user, branch)

    if ran and result then
        currentVersion = result
    end
end

local hasFileIO = globalMethods.readFile and globalMethods.writeFile
local hasFolderFunctions = globalMethods.isFolder and globalMethods.makeFolder
local shouldRefresh = false

if hasFileIO then
    ensureCacheFolders(user)

    local ran, version = pcall(globalMethods.readFile, "__oh_version.txt")
    shouldRefresh = not ran or version ~= currentVersion

    if shouldRefresh then
        globalMethods.writeFile("__oh_version.txt", currentVersion)
    end
end

function environment.import(asset)
    if importCache[asset] then
        return unpack(importCache[asset])
    end

    local assets

    if asset:find("rbxassetid://", 1, true) then
        assets = { game:GetObjects(asset)[1] }
    elseif web then
        local content

        if hasFileIO then
            local file = cacheFilePath(asset, hasFolderFunctions, user)

            if not shouldRefresh then
                local canReadCache = true

                if globalMethods.isFile then
                    canReadCache = globalMethods.isFile(file)
                end

                if canReadCache then
                    local ran, result = pcall(globalMethods.readFile, file)

                    if ran then
                        content = result
                    end
                end
            end

            if not content then
                content = httpGet(rawAssetUrl(user, branch, asset))
                globalMethods.writeFile(file, content)
            end
        else
            content = httpGet(rawAssetUrl(user, branch, asset))
        end

        assets = { loadstring(content, asset .. ".lua")() }
    else
        assets = { loadstring(globalMethods.readFile("hydroxide/" .. asset .. ".lua"), asset .. ".lua")() }
    end

    importCache[asset] = assets
    return unpack(assets)
end

useMethods({
    import = environment.import,
    httpGet = httpGet,
    resolveBranchVersion = resolveBranchVersion
})

useMethods(import("methods/string"))
useMethods(import("methods/table"))
useMethods(import("methods/userdata"))
useMethods(import("methods/environment"))

--import("ui/main")
