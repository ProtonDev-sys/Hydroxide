local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
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

local function resolveBranchVersion(payload)
    return payload and payload.commit and payload.commit.sha
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
        resolveBranchVersion({
            commit = {
                sha = "91327d015db39a7e39e674075f45ee8304aad0aa"
            }
        }),
        "91327d015db39a7e39e674075f45ee8304aad0aa",
        "branch sha extraction"
    )
end

print("compat_spec.lua: ok")
