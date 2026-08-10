local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, label)
    if not value then
        error(label .. ": expected truthy value", 2)
    end
end

local function pick(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)

        if value ~= nil then
            return value
        end
    end
end

local function aliasLegacyMethods(canonical)
    local methods = {
        checkcaller = canonical.checkcaller,
        getgc = canonical.getgc,
        hookmetamethod = canonical.hookmetamethod,
        readfile = canonical.readfile
    }

    methods.checkCaller = methods.checkcaller
    methods.getGc = methods.getgc
    methods.hookMetaMethod = methods.hookmetamethod
    methods.readFile = methods.readfile

    return methods
end

local function httpGet(capabilities, url)
    if capabilities.request then
        local response = capabilities.request({
            Url = url,
            Method = "GET"
        })

        if response and response.Success then
            return response.Body
        end
    end

    if capabilities.httpGet then
        local ok, result = pcall(capabilities.httpGet, url)

        if ok then
            return result
        end
    end

    return capabilities.httpGetAsync(url)
end

local function resolveRefVersion(payload)
    return payload and (payload.sha or (payload.commit and payload.commit.sha))
end

local function getLuaClosures(capabilities)
    if capabilities.filtergc then
        local ran, closures = pcall(capabilities.filtergc, "function", {
            IgnoreExecutor = true
        }, false)

        if ran and type(closures) == "table" then
            local filtered = {}

            for _, closure in pairs(closures) do
                if not capabilities.islclosure or capabilities.islclosure(closure) then
                    filtered[#filtered + 1] = closure
                end
            end

            return filtered
        end
    end

    local filtered = {}

    for _, object in pairs(capabilities.getgc(false)) do
        if type(object) == "function"
            and (not capabilities.islclosure or capabilities.islclosure(object))
            and (not capabilities.isexecutorclosure or not capabilities.isexecutorclosure(object))
        then
            filtered[#filtered + 1] = object
        end
    end

    return filtered
end

do
    local methods = aliasLegacyMethods({
        checkcaller = "checkcaller",
        getgc = "getgc",
        hookmetamethod = "hookmetamethod",
        readfile = "readfile"
    })

    assertEqual(methods.checkCaller, "checkcaller", "legacy checkCaller alias")
    assertEqual(methods.getGc, "getgc", "legacy getGc alias")
    assertEqual(methods.hookMetaMethod, "hookmetamethod", "legacy hookMetaMethod alias")
    assertEqual(methods.readFile, "readfile", "legacy readFile alias")
end

do
    local calls = {}
    local result = httpGet({
        request = function(_)
            calls[#calls + 1] = "request"
            return {
                Success = true,
                Body = "request-body"
            }
        end,
        httpGet = function(_)
            calls[#calls + 1] = "HttpGet"
            return "httpget-body"
        end,
        httpGetAsync = function(_)
            calls[#calls + 1] = "HttpGetAsync"
            return "async-body"
        end
    }, "https://example.invalid")

    assertEqual(result, "request-body", "request preferred")
    assertEqual(table.concat(calls, ","), "request", "request short-circuits")
end

do
    local calls = {}
    local result = httpGet({
        request = function(_)
            calls[#calls + 1] = "request"
            return {
                Success = false
            }
        end,
        httpGet = function(_)
            calls[#calls + 1] = "HttpGet"
            return "httpget-body"
        end,
        httpGetAsync = function(_)
            calls[#calls + 1] = "HttpGetAsync"
            return "async-body"
        end
    }, "https://example.invalid")

    assertEqual(result, "httpget-body", "HttpGet fallback")
    assertEqual(table.concat(calls, ","), "request,HttpGet", "HttpGet used after failed request")
end

do
    local calls = {}
    local result = httpGet({
        httpGet = function(_)
            calls[#calls + 1] = "HttpGet"
            error("unsupported")
        end,
        httpGetAsync = function(_)
            calls[#calls + 1] = "HttpGetAsync"
            return "async-body"
        end
    }, "https://example.invalid")

    assertEqual(result, "async-body", "HttpGetAsync fallback")
    assertEqual(table.concat(calls, ","), "HttpGet,HttpGetAsync", "HttpGetAsync used last")
end

do
    assertEqual(
        resolveRefVersion({
            commit = {
                sha = "91327d015db39a7e39e674075f45ee8304aad0aa"
            }
        }),
        "91327d015db39a7e39e674075f45ee8304aad0aa",
        "branch sha extraction"
    )

    assertEqual(
        resolveRefVersion({
            sha = "86f75436fb8c230d41ca7c76cb506d0f655d13ee"
        }),
        "86f75436fb8c230d41ca7c76cb506d0f655d13ee",
        "commit sha extraction"
    )
end

do
    local luaClosure = function() end
    local cClosure = function() end
    local filterCalls = 0
    local closures = getLuaClosures({
        filtergc = function(filterType, options, filterOne)
            filterCalls = filterCalls + 1
            assertEqual(filterType, "function", "filtergc type")
            assertTrue(options.IgnoreExecutor, "filtergc ignores executor closures")
            assertEqual(filterOne, false, "filtergc returns all matches")
            return { luaClosure, cClosure }
        end,
        islclosure = function(value)
            return value ~= cClosure
        end
    })

    assertEqual(filterCalls, 1, "filtergc preferred")
    assertEqual(#closures, 1, "C closures removed")
    assertEqual(closures[1], luaClosure, "Lua closure retained")
end

do
    local gameClosure = function() end
    local executorClosure = function() end
    local closures = getLuaClosures({
        getgc = function(includeTables)
            assertEqual(includeTables, false, "fallback excludes GC tables")
            return { {}, gameClosure, executorClosure }
        end,
        islclosure = function()
            return true
        end,
        isexecutorclosure = function(value)
            return value == executorClosure
        end
    })

    assertEqual(#closures, 1, "fallback filters executor closure")
    assertEqual(closures[1], gameClosure, "fallback retains game closure")
end

print("compat_spec.lua: ok")
